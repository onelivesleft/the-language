/* eslint-disable @typescript-eslint/naming-convention */
/* eslint-disable curly */


import * as vscode from 'vscode';
import proc = require('child_process');
import path = require('path');
import fs = require('fs');
import { start } from 'repl';

import { languages } from "./languages";
import { resourceLimits } from 'worker_threads';
import { triggerAsyncId } from 'async_hooks';
import { debug } from 'console';

const SELECTOR: vscode.DocumentFilter = { language: 'jai', scheme: 'file' };

let editTimeout: NodeJS.Timer | undefined = undefined;
let saveTimeout: NodeJS.Timer | undefined = undefined;
let selections: Array<vscode.Selection> = [];
let decorationRanges: vscode.Range [] = [];
let selectionsIntersectDecoration = false;
let sentinel = "\nfe955110-fc9e-4c28-be65-93cdffdb26c9\n";
let asmRanges: vscode.Range [] = [];
let asmCompletions: vscode.CompletionItem[];
let asmURLs: { [id: string] : string; } = {};
let locationByFilepath : { [id: string] : vscode.Location [] []} = {};
let foundSomeLocations = false;


export function activate(context: vscode.ExtensionContext) {
	updateConfig();

	context.subscriptions.push(vscode.languages.registerReferenceProvider(SELECTOR, new JaiReferenceProvider()));
	context.subscriptions.push(vscode.languages.registerDefinitionProvider(SELECTOR, new JaiDefinitionProvider()));
	context.subscriptions.push(vscode.languages.registerRenameProvider(SELECTOR, new JaiRenameProvider()));
	context.subscriptions.push(vscode.languages.registerCompletionItemProvider(SELECTOR, new JaiCompletionItemProvider()));

	if (activeEditor) {
		triggerUpdateDecorations();
		triggerUpdateReferences(activeEditor.document.fileName);
	}

	context.subscriptions.push(vscode.workspace.onDidChangeConfiguration(e => {
		updateConfig();
	}));

	vscode.workspace.onDidOpenTextDocument(event => {
		triggerUpdateReferences(event.fileName);
	}, null, context.subscriptions);

	vscode.workspace.onDidSaveTextDocument(event => {
		triggerUpdateReferences(event.fileName);
	}, null, context.subscriptions);

	vscode.window.onDidChangeActiveTextEditor(editor => {
		activeEditor = editor;
		if (editor) {
			updateSelectionAndDecorations();
		}
	}, null, context.subscriptions);

	vscode.workspace.onDidChangeTextDocument(event => {
		if (activeEditor && event.document === activeEditor.document) {
			triggerUpdateDecorations();
		}
	}, null, context.subscriptions);

	vscode.window.onDidChangeTextEditorSelection(event => {
		if (activeEditor === event.textEditor) {
			selections = [];
			for(let i = 0; i < event.selections.length; i++)
				selections.push(event.selections[i]);
			selections.sort((r1,r2) => {
				if (r1.start.line > r2.start.line)
					return +1;
				else if (r1.start.line < r2.start.line)
					return -1;

				if (r1.start.character > r2.start.character)
					return +1;
				else if (r1.start.character < r2.start.character)
					return -1;

				return 0;
			});
			if (selectionsIntersectDecoration || areIntersecting(selections, decorationRanges)) {
				updateDecorations();
			}
		}
	});

	asmCompletions = loadAsmCompletions();
}

export function deactivate() {}

function loadAsmCompletions(): vscode.CompletionItem[] {
	let items: vscode.CompletionItem[] = [];

	let extension = vscode.extensions.getExtension("onelivesleft.the-language");
	if (extension === undefined) return items;
	let modulepath = path.sep === "\\"
		? path.join(extension.extensionPath, extension.extensionPath.toLowerCase().startsWith("c:\\repos") ? "src" : "out").replace(/\//, '\\')
		: path.join(extension.extensionPath, "out");

	let asmJSON = fs.readFileSync(path.resolve(modulepath, "asmCommands.json"), "utf8");
	let completions = JSON.parse(asmJSON);

	for (const completion in completions) {
		let info = completions[completion];
		let name = completion.padEnd(20, " ");
		let detail : string = info.detail[0];
		let first_doc_line : string = "";
		if (info.documentation !== undefined)
			first_doc_line = info.documentation[0];

		if (!detail) detail = first_doc_line;
		name += detail;

		let item = new vscode.CompletionItem(name, vscode.CompletionItemKind.Keyword);
		item.insertText = completion;

		// A human-readable string with additional information
		// about this item, like type or symbol information.
		item.detail = detail;

		// A human-readable string that represents a doc-comment.
		if (info.documentation !== undefined) {
			item.documentation = "";
			let doubleLine = true;
			for (let i = 0; i < info.documentation.length; i++) {
				if (info.documentation[i] === "Flags Affected:")
					doubleLine = false;
				item.documentation += info.documentation[i] + "\n";
				if (doubleLine) item.documentation += "\n";
			}
		}

		if (info.operands) {
			if (item.documentation)
				item.documentation = " " + info.operands.join("\n ") + "\n\n" + item.documentation;
			else
				item.documentation = " " + info.operands.join("\n ");
		}

		let url : string = info.url;
		asmURLs[completion] = url;

		items.push(item);
	}

	return items;
}



function triggerUpdateReferences(filepath: string) {
	if (!filepath.endsWith(".jai")) return;

	if (saveTimeout) {
		clearTimeout(saveTimeout);
		saveTimeout = undefined;
	}
	saveTimeout = setTimeout(function () { updateReferences(filepath); }, 500);
}


let currentlyRunningReferenceUpdate = false;
let referenceUpdateAttempts = 0;
const maxReferenceUpdateAttempts = 10;

function updateReferences(filepath: string) {
	if (currentlyRunningReferenceUpdate) {
		referenceUpdateAttempts += 1;
		if (referenceUpdateAttempts < maxReferenceUpdateAttempts) {
			if (debugMode) console.log("Already running reference update, rescheduling...");
			triggerUpdateReferences(filepath);
			return;
		}
		else {
			if (debugMode) console.log("Already running reference update, killing old process...");
		}
	}

	referenceUpdateAttempts = 0;
	currentlyRunningReferenceUpdate = true;
	if (debugMode) console.log("Running reference update...");

	jaiDump(filepath).then(output => {
		if (output === undefined || output === "") {
			currentlyRunningReferenceUpdate = false;
			if (debugMode) console.log("Reference update complete.");
			if (debugMode) console.log("No output");
			return;
		}

		locationByFilepath = {};
		foundSomeLocations = false;
		let result : vscode.Location[] = [];
		for (let row of output.split("\n")) {
			if (!row.trim()) {
				if (result.length) {
					foundSomeLocations = true;
					let done : { [id: string] : boolean } = {};
					for (let i = 0; i < result.length; i++) {
						let fp = result[i].uri.fsPath.toLowerCase();
						let alreadyPresent = done[fp];
						if (!alreadyPresent) {
							done[fp] = true;
							let fileLocations = locationByFilepath[fp];
							if (fileLocations)
								fileLocations.push(result);
							else
								locationByFilepath[fp] = [result];
						}
					}
					result = [];
				}
				continue;
			}
			let items = row.split("|");
			let uri = vscode.Uri.file(items[0]);
			let startPosition = new vscode.Position(parseInt(items[1]) - 1, parseInt(items[2]) - 1);
			let endRow = parseInt(items[3]) - 1;
			let endCol = parseInt(items[4]) - 1;
			if (endRow < 0) endRow = startPosition.line;
			if (endCol < 0) endCol = startPosition.character + 1;
			let endPosition = new vscode.Position(endRow, endCol);
			let location = new vscode.Location(uri, new vscode.Range(startPosition, endPosition));
			result.push(location);
		}

		if (result.length) {
			foundSomeLocations = true;
			let done : { [id: string] : boolean } = {};
			for (let i = 0; i < result.length; i++) {
				let fp = result[i].uri.fsPath.toLowerCase();
				let alreadyPresent = done[fp];
				if (!alreadyPresent) {
					done[fp] = true;
					let fileLocations = locationByFilepath[fp];
					if (fileLocations)
						fileLocations.push(result);
					else
						locationByFilepath[fp] = [result];

				}
			}
		}

		if (debugMode) console.log("Reference update complete.");
		if (debugMode) console.log(foundSomeLocations);
		currentlyRunningReferenceUpdate = false;
	}).catch(output => {
		if (debugMode) {
			console.log("Failed to get references from jai compiler (probably because the code did not compile)");
			console.log("Compiler output:\n" + output);
		}
		currentlyRunningReferenceUpdate = false;
	});
}



function triggerUpdateDecorations() {
	if (editTimeout) {
		clearTimeout(editTimeout);
		editTimeout = undefined;
	}
	editTimeout = setTimeout(updateSelectionAndDecorations, 500);
}

let activeEditor = vscode.window.activeTextEditor;


function updateSelectionAndDecorations() {
	if (!activeEditor) return;

	selections = [];
	let s = activeEditor.selections;
	for(let i = 0; i < s.length; i++)
		selections.push(s[i]);

	updateDecorations();
	updateAsm(activeEditor.document.getText());
}


function updateDecorations() {
	if (!activeEditor) return;

	decorate(activeEditor);
}


function makeDecoration(color: string): vscode.TextEditorDecorationType {
	return vscode.window.createTextEditorDecorationType({
		backgroundColor: color,
		isWholeLine: true,
	});
}


interface EmbedLanguageColor {
	language: string;
	color: string;
}


let debugMode : boolean | undefined = false;
let decorateEmbeds : boolean | undefined = true;
let projectPath : string | undefined = "";
let projectCompilerArgs : string[] = [];
let embedColorsConfig: EmbedLanguageColor[] | undefined;
let embedColors: { [language: string] : string};
let defaultEmbedColor = "#222222";
let embedDecorations: { [color: string] : vscode.TextEditorDecorationType } = {};


function updateConfig() {
	let config = vscode.workspace.getConfiguration('the-language');
	decorateEmbeds = config.get("decorateEmbeds");
	if (decorateEmbeds === undefined) decorateEmbeds = true;

	debugMode = config.get("debugMode");
	if (debugMode === undefined) debugMode = false;

	projectPath = config.get("projectFile");
	if (projectPath === undefined) projectPath = "";

	let args = config.get("projectJaiArgs");
	projectCompilerArgs = args === undefined ? [] : argsFromString(args as string);

	embedColorsConfig = config.get("embedColors");
	const isColor = /#[a-fA-F0-9]{6}/;
	if (embedColorsConfig !== undefined) {
		embedColors = {};
		for (let i = 0; i < embedColorsConfig.length; i++) {
			let embedColor = embedColorsConfig[i];
			if (embedColor.color.match(isColor)) {
				if (!(embedColor.color in embedDecorations))
					embedDecorations[embedColor.color] = makeDecoration(embedColor.color);
				if (embedColor.language.toLowerCase() === "default")
					defaultEmbedColor = embedColor.color;
				else
					embedColors[embedColor.language] = embedColor.color;
			}
		}
	}
	updateSelectionAndDecorations();
}


function argsFromString(args: string): string [] {
	let result : string [] = [];

	args = args.trimLeft();
	while (args) {
		if (args.startsWith("\"")) {
			args = args.slice(1);
			let index = args.indexOf("\"");
			if (index < 0) break;
			result.push(args.slice(0, index));
			args = args.slice(index + 1);
		}
		else {
			let index = args.indexOf(" ");
			if (index < 0) {
				result.push(args);
				break;
			}
			else {
				result.push(args.slice(0, index));
				args = args.slice(index);
			}
		}
		args = args.trimLeft();
	}

	return result;
}


function areIntersecting(rangesA: vscode.Range [], rangesB: vscode.Range []): boolean {
	if (rangesA === undefined || rangesB === undefined) return false;

	for (let i = 0; i < rangesA.length; i++) {
		for (let j = 0; j < rangesB.length; j++) {
			if (rangesA[i] === undefined || rangesB[j] === undefined)
				return false;
			if (rangesA[i].intersection(rangesB[j]))
				return true;
		}
	}
	return false;
}


function subtract(range: vscode.Range, sorted_subtractors: vscode.Range []): [vscode.Range [], boolean] {
	let result: vscode.Range [] = [];
	let remainder: vscode.Range | undefined;
	remainder = range;
	let changed = false;

	for (let i = 0; i < sorted_subtractors.length; i++) {
		let to_remove = sorted_subtractors[i];
		if (to_remove.end.isBeforeOrEqual(remainder.start)) continue;
		if (to_remove.start.isAfterOrEqual(remainder.end)) continue;

		if (to_remove.start.isBeforeOrEqual(remainder.start)) {
			if (to_remove.end.isAfterOrEqual(remainder.end)) {
				changed = true;
				remainder = undefined;
				break;
			}
			else {
				changed = true;
				remainder = new vscode.Range(to_remove.end, remainder.end);
			}
		}
		else if (to_remove.end.isAfterOrEqual(remainder.end)) {
			changed = true;
			result.push(new vscode.Range(remainder.start, to_remove.start));
			remainder = undefined;
			break;
		}
		else { // to_subtract is strictly within range
			changed = true;
			result.push(new vscode.Range(remainder.start, to_remove.start));
			remainder = new vscode.Range(to_remove.end, remainder.end);
		}
	}

	if (remainder)
		result.push(remainder);

	return [result, changed];
}


function decorate(editor: vscode.TextEditor) {
	if (!decorateEmbeds) {
		for (let color in embedDecorations) {
			editor.setDecorations(embedDecorations[color], []);
		}
		return;
	}

	let sourceCode = editor.document.getText();
	let hereString = /#string\s+([a-zA-Z_]\w*)\s*$/;
	let docComment = /^\s*\/\*\*/;

	let decorationsArrays: { [color: string] : vscode.DecorationOptions[] } = {};

	const sourceCodeArr = sourceCode.split('\n');

	let endToken : string | undefined;
	let decorationColor = defaultEmbedColor;
	let startLine = 0;
	let insideDocComment = false;
	decorationRanges = [];

	selectionsIntersectDecoration = false;

	for (let line = 0; line < sourceCodeArr.length; line++) {
		if (endToken !== undefined) {
			let match = sourceCodeArr[line].match(endToken);

			if (match !== null || line === sourceCodeArr.length - 1) {
				endToken = undefined;

				const eol = 99999;
				let endLine = insideDocComment ? line : line - 1;


				let range = new vscode.Range(
					new vscode.Position(startLine, 0),
					new vscode.Position(endLine, eol)
				);
				decorationRanges.push(range);

				if (!(decorationColor in decorationsArrays))
					decorationsArrays[decorationColor] = [];

				let [applicableRanges, changed] = subtract(range, selections); // @Note assumes selections are ordered and disjoint
				if (changed) selectionsIntersectDecoration = true;

				for (let i = 0; i < applicableRanges.length; i++) {
					range = applicableRanges[i];
					if (range.start.character !== 0) {
						if (range.start.line + 1 > range.end.line) continue;
						range = new vscode.Range(
							new vscode.Position(range.start.line + 1, 0),
							range.end
						);
					}
					if (range.end.character !== eol) {
						if (range.end.line - 1 < range.start.line) continue;
						range = new vscode.Range(
							range.start,
							new vscode.Position(range.end.line - 1, eol),
						);
					}

					let decoration = { range };
					decorationsArrays[decorationColor].push(decoration);
				}
			}
		}
		else {
			let match = sourceCodeArr[line].match(hereString);
			let isHereString = true;

			if (match === null || match.index === undefined) {
				match = sourceCodeArr[line].match(docComment);
				isHereString = false;
			}

			if (match !== null && match.index !== undefined) {
				let matchedLanguage: string;
				if (isHereString) {
					startLine = line + 1;
					insideDocComment = false;
					matchedLanguage = match[1];
					endToken = matchedLanguage;
				}
				else {
					startLine = line;
					insideDocComment = true;
					matchedLanguage = "md";
					endToken = "\\*\\/";
				}

				decorationColor = defaultEmbedColor;
				for (let i = 0; i < languages.length; i++) {
					let language = languages[i][0] as string;
					let pattern  = languages[i][1] as RegExp;
					if (matchedLanguage.match(pattern))
					{
						if (language in embedColors)
							decorationColor = embedColors[language];
						break;
					}
				}
			}
		}
	}

	for (let color in decorationsArrays) {
		editor.setDecorations(embedDecorations[color], decorationsArrays[color]);
	}

	for (let color in embedDecorations) {
		if (!(color in decorationsArrays))
			editor.setDecorations(embedDecorations[color], []);
	}
}

function updateAsm(sourceCode: string) {
	let asmStart = /#asm\s+{/;
	let asmEnd = "}";

	const sourceCodeArr = sourceCode.split('\n');

	let startLine = 0;
	let startChar = 0;
	let insideAsm = false;
	asmRanges = [];

	for (let line = 0; line < sourceCodeArr.length; line++) {
		if (insideAsm) {
			let match = sourceCodeArr[line].match(asmEnd);

			if (match !== null || line === sourceCodeArr.length - 1) {
				let eol;
				if (match === null || match.index === undefined)
					eol = 99999;
				else
					eol = match.index + 1;
				let range = new vscode.Range(
					new vscode.Position(startLine, startChar),
					new vscode.Position(line, eol)
				);
				asmRanges.push(range);
				insideAsm = false;
			}
		}
		else {
			let match = sourceCodeArr[line].match(asmStart);
			if (match === null || match.index === undefined) continue;
			let singleLineMatch = sourceCodeArr[line].slice(match.index + match[0].length).match(asmEnd);
			if (singleLineMatch === null || singleLineMatch.index === undefined) {
				insideAsm = true;
				startLine = line;
				startChar = match.index + match[0].length;
			}
			else {
				let range = new vscode.Range(
					new vscode.Position(line, match.index + match[0].length),
					new vscode.Position(line, match.index + match[0].length + singleLineMatch.index + 1)
				);

				asmRanges.push(range);
			}
		}
	}
}


class JaiCompletionItemProvider implements vscode.CompletionItemProvider {
	public provideCompletionItems(document: vscode.TextDocument, position: vscode.Position,
								  token: vscode.CancellationToken, context: vscode.CompletionContext):
		Thenable<vscode.CompletionItem[]> {
		return new Promise((resolve, reject) => {
			let invalidCharacter = /[^a-z0-9]/;
			for (let i = 0; i < asmRanges.length; i++) {
				let range = asmRanges[i];
				if (range.contains(position)) {
					let line = document.getText().split("\n")[position.line];
					let startPos, endPos;
					const eol = 99999;
					if (position.line === range.start.line)
						startPos = range.start.character;
					else
						startPos = 0;
					if (position.line === range.end.line)
						endPos = range.end.character;
					else
						endPos = eol;
					line = line.slice(startPos, min(position.character, endPos));
					let semicolon = line.lastIndexOf(";");
					if (semicolon >= 0)
					 	line = line.slice(semicolon + 1);
					line = line.trimLeft();
					let match = line.match(invalidCharacter);
					if (match === null)
						resolve(asmCompletions);
					else
						reject();
					return;
				}
			}
			reject();
		});
    }
}


class JaiReferenceProvider implements vscode.ReferenceProvider {
	public provideReferences(document: vscode.TextDocument, position: vscode.Position,
							 options: { includeDeclaration: boolean }, token: vscode.CancellationToken):
	Thenable<vscode.Location[]> {
		return new Promise((resolve, reject) => {
			for (let i = 0; i < asmRanges.length; i++) {
				let range = asmRanges[i];
				if (range.contains(position)) {
					reject();
					return;
				}
			}

			console.log(foundSomeLocations);
			console.log(locationByFilepath);

			if (foundSomeLocations) {
				let locations = findLocations(document.uri, position);
				if (locations.length === 0)
					reject();
				else
					resolve(locations);
			}
			else {
				jaiLocate(document.fileName, position, "Reference").then(output => {
					if (output === undefined) {
						reject();
					}
					else {
						let locations = locationsFromString(output);
						resolve(locations);
					}
				});
			}
		});
    }
}


class JaiDefinitionProvider implements vscode.DefinitionProvider {
	public provideDefinition(document: vscode.TextDocument, position: vscode.Position,
							 token: vscode.CancellationToken):
	vscode.ProviderResult<vscode.Definition | vscode.DefinitionLink[]> {
		return new Promise<vscode.Definition>((resolve, reject) => {
			if (path.basename(document.fileName).startsWith(".added_strings_")) {
				// @Robustness This relies on .added_strings formatting being a block
				// of 3 comments above the code block, with the middle row containing
				// the location. i.e.:
//
// #insert text. Generated from C:/Repos/jaitest/concat.jai:7.
//
				let row = position.line;
				let text = document.getText();
				let lines = text.split("\n");
				let encoded_location = /\/\/ .*Generated from (.*):([0-9]+)\./;

				while (row < document.lineCount && lines[row].startsWith("//"))
					row += 1;
				while (row >= 0 && !lines[row].startsWith("//"))
					row -= 1;
				row -= 1;
				if (row < 0) reject();

				let m = lines[row].match(encoded_location);
				if (m !== null && m !== undefined) {
					let uri = vscode.Uri.file(m[1]);
					let posRow = parseInt(m[2]) - 1;
					let startPosition = new vscode.Position(posRow, 0);
					let endPosition = new vscode.Position(posRow, 0);
					let location = new vscode.Location(uri, new vscode.Range(startPosition, endPosition));
					let result : vscode.Location[] = [];
					result.push(location);
					resolve(result);
				}
				else {
					reject();
				}
			}
			else {
				// @TODO When the VSLocate can find idents in #asm blocks refine this
				//       (right now if you're in an #asm block it will never attempt to id,
				//        it will always just try to go to website)
				for (let i = 0; i < asmRanges.length; i++) {
					let range = asmRanges[i];
					if (range.contains(position)) {
						let wordRange = document.getWordRangeAtPosition(position);
						if (wordRange !== undefined) {
							let line = document.getText().split("\n")[position.line];
							let word = line.slice(wordRange.start.character, wordRange.end.character);
							let url = asmURLs[word];
							if (url === undefined) {
								reject();
							}
							else {
								vscode.env.openExternal(vscode.Uri.parse(url));
								reject();
							}
						}
						return;
					}
				}

				if (foundSomeLocations) {
					let locations = findLocations(document.uri, position);
					if (locations.length === 0)
						reject();
					else
						resolve(locations[0]);
				}
				else {
					jaiLocate(document.fileName, position, "Definition").then(output => {
						if (output === undefined) {
							reject();
						}
						else {
							let locations = locationsFromString(output, true);
							resolve(locations[0]);
						}
					});
				}
			}
		});
	}
}


class JaiRenameProvider implements vscode.RenameProvider {
	public provideRenameEdits(document: vscode.TextDocument, position: vscode.Position, newName: string,
							  token: vscode.CancellationToken):
	Thenable<vscode.WorkspaceEdit> {
		return new Promise<vscode.WorkspaceEdit>((resolve, reject) => {
			jaiLocate(document.fileName, position, "Rename").then(output => {
				if (output === undefined) {
					reject();
				}
				else {
					let locations = locationsFromString(output);
					let result = new vscode.WorkspaceEdit();
					for (let i = 0; i < locations.length; i++) {
						let location = locations[i];
						if (debugMode) console.log(location.uri.fsPath);
						result.replace(location.uri, location.range, newName);
					}
					if (debugMode) console.log(result);
					resolve(result);
				}
			});
		});
	}
}


async function jaiLocate(filepath: string, position: vscode.Position, operation: string): Promise<string | undefined> {
	let config = vscode.workspace.getConfiguration('the-language');
	let exe_path = config.get("pathToJaiExecutable");
	if (exe_path === undefined) return;

	if (debugMode) console.log("projectPath is [" + projectPath + "]");
	let fileToCompile = projectPath !== "" ? projectPath as string : filepath;

	let extension = vscode.extensions.getExtension("onelivesleft.the-language");
	if (extension === undefined) return;
	let modulepath = path.sep === "\\"
		? path.join(extension.extensionPath, extension.extensionPath.toLowerCase().startsWith("c:\\repos") ? "src" : "out").replace(/\//, '\\')
		: path.join(extension.extensionPath, "out");

	let normalized = filepath.replace(/\\/g, '/');

	let args : string [] = [
		"-import_dir",
		modulepath,
		"-meta",
		"VSCodeLocate",
		fileToCompile,
		"-no_dce"
	];

	for (let i = 0; i < projectCompilerArgs.length; i++)
		args.push(projectCompilerArgs[i]);

	args.push("--");
	args.push("Find");
	args.push(normalized);
	args.push((position.line + 1).toString());
	args.push((position.character + 1).toString());

	if (debugMode) console.log(exe_path, args);
	return execCommand(exe_path as string, args);
}


async function jaiDump(filepath: string): Promise<string | undefined> {
	let config = vscode.workspace.getConfiguration('the-language');
	let exe_path = config.get("pathToJaiExecutable");
	if (exe_path === undefined) return;

	if (debugMode) console.log("projectPath is [" + projectPath + "]");
	let fileToCompile = projectPath !== "" ? projectPath as string : filepath;

	let extension = vscode.extensions.getExtension("onelivesleft.the-language");
	if (extension === undefined) return;
	let modulepath = path.sep === "\\"
		? path.join(extension.extensionPath, extension.extensionPath.toLowerCase().startsWith("c:\\repos") ? "src" : "out").replace(/\//, '\\')
		: path.join(extension.extensionPath, "out");

	let normalized = filepath.replace(/\\/g, '/');

	let args : string [] = [
		"-import_dir",
		modulepath,
		"-meta",
		"VSCodeLocate",
		fileToCompile,
		"-no_dce"
	];

	for (let i = 0; i < projectCompilerArgs.length; i++)
		args.push(projectCompilerArgs[i]);

	args.push("--");
	args.push("Dump");

	if (debugMode) console.log(exe_path, args);
	return spawnCommand(exe_path as string, args);
}


function execCommand(exe_path: string, args: string[]): Promise<string | undefined> {
	return new Promise((resolve, reject) => {
		proc.execFile(exe_path, args, (error, stdout, stderr) => {
			if (error) {
				console.log(error);
				console.log(stderr);
				reject(error);
			}
			else {
				if (debugMode) console.log(stdout);
				let index = stdout.indexOf(sentinel);
				if (index < 0)
					reject();
				else
					resolve(stdout.slice(index + sentinel.length));
			}
		});
	});
}


let spawnedChild : proc.ChildProcessWithoutNullStreams | null;

function spawnCommand(exe_path: string, args: string[]): Promise<string | undefined> {
	return new Promise((resolve, reject) => {
		if (spawnedChild) spawnedChild.kill();

		spawnedChild = proc.spawn(exe_path, args);
		let data : string [] = [];
		let errors : string [] = [];

		spawnedChild.stdout.on('data', chunk => {
			data.push(chunk);
		});

		spawnedChild.stderr.on('data', chunk => {
			errors.push(chunk);
		});

		spawnedChild.on('exit', code => {
			spawnedChild = null;
			if (code)
				reject("Error: " + code + "\n" + errors.join(""));
			else {
				let stdout = data.join("");
				if (debugMode) console.log(stdout);
				let index = stdout.indexOf(sentinel);
				if (index < 0)
					reject(errors.join("") + "\n" + stdout);
				else
					resolve(stdout.slice(index + sentinel.length));
			}
		});
	});
}


function locationsFromString(locations: string, firstLineOnly: boolean = false): vscode.Location[] {
	//console.log(locations);
	let result : vscode.Location[] = [];
	for (let row of locations.split("\n")) {
		if (!row.trim()) continue;
		let items = row.split("|");
		let uri = vscode.Uri.file(items[0]);
		let startPosition = new vscode.Position(parseInt(items[1]) - 1, parseInt(items[2]) - 1);
		let endPosition = new vscode.Position(parseInt(items[3]) - 1, parseInt(items[4]) - 1);
		let location = new vscode.Location(uri, new vscode.Range(startPosition, endPosition));
		result.push(location);
		if (firstLineOnly) break;
	}

	return result;
}


function findLocations(uri: vscode.Uri, position: vscode.Position): vscode.Location[] {
	let fileLocations = locationByFilepath[uri.fsPath.toLowerCase()];
	if (!fileLocations) return [];

	for (let i = 0; i < fileLocations.length; i++) {
		let locations = fileLocations[i];
		for (let l = 0; l < locations.length; l++) {
			let location = locations[l];
			if (location.range.contains(position))
				return locations;
		}
	}

	return [];
}


function min(a: number, b: number): number {
	if (a <= b) return a; else return b;
}
