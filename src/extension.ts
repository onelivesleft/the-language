/* eslint-disable @typescript-eslint/naming-convention */
/* eslint-disable curly */


import {Selection, Range, DocumentFilter, CompletionItem, Location, Position, ProviderResult, FoldingRangeKind, IndentAction} from 'vscode';
import {ExtensionContext, languages, workspace, window, extensions, CompletionItemKind} from 'vscode';
import {Uri, Diagnostic, DiagnosticSeverity, DiagnosticRelatedInformation, TextEditorDecorationType} from 'vscode';
import {TextEditor, DecorationOptions, CompletionItemProvider, TextDocument, CancellationToken} from 'vscode';
import {CompletionContext, FoldingRangeProvider, ReferenceProvider, FoldingRange} from 'vscode';
import {DefinitionProvider, Definition, DefinitionLink, env, RenameProvider, WorkspaceEdit} from 'vscode';
import proc = require('child_process');
import path = require('path');
import fs = require('fs');
import { start } from 'repl';

import { supportedLanguages } from "./languages";
import { resourceLimits } from 'worker_threads';
import { triggerAsyncId } from 'async_hooks';
import { debug } from 'console';
import { inflate } from 'zlib';
import { resolve } from 'dns';

const SELECTOR: DocumentFilter = { language: 'jai', scheme: 'file' };

let editTimeout: NodeJS.Timer | undefined = undefined;
let saveTimeout: NodeJS.Timer | undefined = undefined;
let selections: Array<Selection> = [];
let decorationRanges: Range [] = [];
let selectionsIntersectDecoration = false;
let sentinel = "\nfe955110-fc9e-4c28-be65-93cdffdb26c9\n";
let asmRanges: Range [] = [];
let asmCompletions: CompletionItem [] = [];
let asmURLs: { [id: string] : string; } = {};
let foldingRanges: FoldingRange [] = [];

interface Reference {
	name: string;
	locations: Location [];
}
let referenceByFilepath : { [id: string] : Reference []} = {};
let foundSomeReferences = false;

let errorProblemMatcher = /(([a-zA-Z]:)?[^:]*):(\d+),(\d+):\s+(Error):\s+([^\n]*)/;
let warningProblemMatcher = /(([a-zA-Z]:)?[^:]*):(\d+),(\d+):\s+(Warning):\s+([^\n]*)/;
let infoProblemMatcherWindows = /(.*?)(\(?([a-zA-Z]:[^\\:*?"<>|\t\n\r]+):(\d+)(,(\d+))?\)?)(.*)/;
let infoProblemMatcherLinux = /(.*?)(\(?(\/[^\\:*?"<>|\t\n\r]+):(\d+)(,(\d+))?\)?)(.*)/;
let infoProblemMatcher : RegExp;
let diagnosticCollection = languages.createDiagnosticCollection();


export function activate(context: ExtensionContext) {
	updateConfig();

	infoProblemMatcher = path.sep === "\\" ? infoProblemMatcherWindows : infoProblemMatcherLinux;

	context.subscriptions.push(languages.registerReferenceProvider(SELECTOR, new JaiReferenceProvider()));
	context.subscriptions.push(languages.registerDefinitionProvider(SELECTOR, new JaiDefinitionProvider()));
	context.subscriptions.push(languages.registerRenameProvider(SELECTOR, new JaiRenameProvider()));
	context.subscriptions.push(languages.registerCompletionItemProvider(SELECTOR, new JaiCompletionItemProvider()));
	context.subscriptions.push(languages.registerFoldingRangeProvider(SELECTOR, new JaiFoldingRangeProvider()));

	if (activeEditor) {
		triggerUpdateDecorations();
		triggerUpdateReferences(activeEditor.document.fileName);
	}

	context.subscriptions.push(workspace.onDidChangeConfiguration(e => {
		updateConfig();
	}));

	workspace.onDidOpenTextDocument(event => {
		triggerUpdateReferences(event.fileName);
	}, null, context.subscriptions);

	workspace.onDidSaveTextDocument(event => {
		triggerUpdateReferences(event.fileName);
	}, null, context.subscriptions);

	window.onDidChangeActiveTextEditor(editor => {
		activeEditor = editor;
		if (editor) {
			updateSelectionAndDecorations();
		}
	}, null, context.subscriptions);

	workspace.onDidChangeTextDocument(event => {
		if (activeEditor && event.document === activeEditor.document) {
			triggerUpdateDecorations();
		}
	}, null, context.subscriptions);

	window.onDidChangeTextEditorSelection(event => {
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
}

export function deactivate() {}

function loadAsmCompletions(): CompletionItem[] {
	let items: CompletionItem[] = [];

	let extension = extensions.getExtension("onelivesleft.the-language");
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

		let item = new CompletionItem(name, CompletionItemKind.Keyword);
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

	let uri = Uri.file(filepath);
	for (let i = 0; i < workspace.textDocuments.length; i++) {
		let document = workspace.textDocuments[i];
		if (document.uri.path === uri.path) {
			if (!document.getText().match(/^\s*main\s+::/gm)) {
				if (debugMode) console.log("No main in " + filepath);
				return;
			}
		}
	}

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
		if (output === undefined || output[0] === "") {
			currentlyRunningReferenceUpdate = false;
			if (debugMode) console.log("Reference update complete.");
			if (debugMode) console.log("No output");
			return;
		}

		let referenceOutput = output[0];
		let errorOutput = output[1];

		referenceByFilepath = {};
		foundSomeReferences = false;
		let result : Reference = { name: "", locations: []};
		for (let row of referenceOutput.split("\n")) {
			if (!row.trim()) {
				if (result.locations.length) {
					foundSomeReferences = true;
					let done : { [id: string] : boolean } = {};
					for (let i = 0; i < result.locations.length; i++) {
						let fp = result.locations[i].uri.fsPath.toLowerCase();
						let alreadyPresent = done[fp];
						if (!alreadyPresent) {
							done[fp] = true;
							let fileReferences = referenceByFilepath[fp];
							if (fileReferences)
								fileReferences.push(result);
							else
								referenceByFilepath[fp] = [result];
						}
					}
					result = { name: "", locations: []};
				}
				continue;
			}
			let items = row.split("|");
			if (items[0]) result.name = items[0];
			let uri = Uri.file(items[1]);
			let startPosition = new Position(parseInt(items[2]) - 1, parseInt(items[3]) - 1);
			let endRow = parseInt(items[4]) - 1;
			let endCol = parseInt(items[5]) - 1;
			if (endRow < 0) endRow = startPosition.line;
			if (endCol < 0) endCol = startPosition.character + 1;
			let endPosition = new Position(endRow, endCol);
			let location = new Location(uri, new Range(startPosition, endPosition));
			result.locations.push(location);
		}

		if (result.locations.length) {
			foundSomeReferences = true;
			let done : { [id: string] : boolean } = {};
			for (let i = 0; i < result.locations.length; i++) {
				let fp = result.locations[i].uri.fsPath.toLowerCase();
				let alreadyPresent = done[fp];
				if (!alreadyPresent) {
					done[fp] = true;
					let fileReferences = referenceByFilepath[fp];
					if (fileReferences)
						fileReferences.push(result);
					else
						referenceByFilepath[fp] = [result];
				}
			}
		}

		if (debugMode) console.log("Reference update complete.");
		if (debugMode) console.log(foundSomeReferences);

		let match = errorOutput.match(warningProblemMatcher);
		if (match) {
			let diagnostics : Array<[Uri, Diagnostic[] | undefined]> = [];
			while (match) {
				let filename = match[1];
				let position = new Position(parseInt(match[3]) - 1, parseInt(match[4]) - 1);
				let message = match[6];
				let tail = match[7];
				diagnostics.push([Uri.file(filename), [new Diagnostic(new Range(position, position), message, DiagnosticSeverity.Warning)]]);
				if (match.index !== undefined) {
					errorOutput = errorOutput.substring(match.index + match[0].length);
					match = errorOutput.match(warningProblemMatcher);
				}
				else {
					match = null;
				}
			}
			diagnosticCollection.set(diagnostics);
		}
		else {
			diagnosticCollection.clear();
		}

		currentlyRunningReferenceUpdate = false;
	}).catch(output => {
		if (debugMode) {
			console.log("Compiler output:\n" + output);
		}

		let text = output as string;
		let match = text.match(errorProblemMatcher);
		if (match) {
			let filename = match[1];
			let diagnosticUri = Uri.file(filename);
			let position = new Position(parseInt(match[3]) - 1, parseInt(match[4]) - 1);
			let message = match[6];
			let diagnostic = [new Diagnostic(new Range(position, position), message, DiagnosticSeverity.Error)];
			let related : DiagnosticRelatedInformation [] = [];
			if (match.index !== undefined) {
				let tail = text.substring(match.index + match[0].length);
				match = tail.match(infoProblemMatcher);
				if (match && match.index !== undefined) {
					while (match && match.index !== undefined) {
						console.log(match);
						let startIndex = match.index;
						filename = match[3];
						if (match[6])
							position = new Position(parseInt(match[4]) - 1, parseInt(match[6]) - 1);
						else
							position = new Position(parseInt(match[4]) - 1, 0);
						let offset = match.index + match[0].length;
						let locationString = match[2];
						let remainder = tail.substring(offset);
						match = remainder.match(infoProblemMatcher);
						let endIndex : number;
						if (match && match.index !== undefined)
							endIndex = match.index + offset;
						else
							endIndex = tail.length;
						message = tail.substring(startIndex, endIndex).replace(locationString, "");
						related.push(new DiagnosticRelatedInformation(new Location(Uri.file(filename), position), message));
						tail = remainder;
					}
					diagnostic[0].relatedInformation = related;
				}
			}
			diagnosticCollection.set(diagnosticUri, diagnostic);
		}
		else {
			diagnosticCollection.clear();
			console.log("Failed to parse jai error:" + output);
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

let activeEditor = window.activeTextEditor;


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


function makeDecoration(color: string): TextEditorDecorationType {
	return window.createTextEditorDecorationType({
		backgroundColor: color,
		isWholeLine: true,
	});
}


interface EmbedLanguageColor {
	language: string;
	color: string;
}


let debugMode : boolean | undefined = false;
let useCompiler : boolean | undefined = true;
let decorateEmbeds : boolean | undefined = true;
let projectPath : string | undefined = "";
let projectCompilerArgs : string[] = [];
let embedColorsConfig: EmbedLanguageColor[] | undefined;
let embedColors: { [language: string] : string};
let defaultEmbedColor = "#222222";
let embedDecorations: { [color: string] : TextEditorDecorationType } = {};


function updateConfig() {
	let config = workspace.getConfiguration('the-language');
	useCompiler = config.get("enableBackgroundCompilation");
	if (useCompiler === undefined) useCompiler = true;

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


function areIntersecting(rangesA: Range [], rangesB: Range []): boolean {
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


function subtract(range: Range, sorted_subtractors: Range []): [Range [], boolean] {
	let result: Range [] = [];
	let remainder: Range | undefined;
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
				remainder = new Range(to_remove.end, remainder.end);
			}
		}
		else if (to_remove.end.isAfterOrEqual(remainder.end)) {
			changed = true;
			result.push(new Range(remainder.start, to_remove.start));
			remainder = undefined;
			break;
		}
		else { // to_subtract is strictly within range
			changed = true;
			result.push(new Range(remainder.start, to_remove.start));
			remainder = new Range(to_remove.end, remainder.end);
		}
	}

	if (remainder)
		result.push(remainder);

	return [result, changed];
}


enum FoldType {
	Import, Comment, Block
}

function decorate(editor: TextEditor) {
	if (!decorateEmbeds) {
		for (let color in embedDecorations) {
			editor.setDecorations(embedDecorations[color], []);
		}
		return;
	}

	let sourceCode = editor.document.getText();
	let hereString = /#string\s+([a-zA-Z_]\w*)\s*$/;
	let blockComment = /^\s*\/\*/;
	let docComment = /^\s*\/\*\*/;

	let decorationsArrays: { [color: string] : DecorationOptions[] } = {};

	const sourceCodeArr = sourceCode.split('\n');

	let endToken : string | undefined;
	let decorationColor = defaultEmbedColor;
	let startLine = 0;
	let insideDocComment = false;
	let insideBlockComment = false;
	let commentDepth = 0;
	decorationRanges = [];
	foldingRanges = [];

	let regionStart = -1;
	let importStart = -1;
	let commentStart = -1;
	let blockStart = -1;
	let parenStart = -1;

	selectionsIntersectDecoration = false;
	let trimmedLineText : string = "";

	for (let line = 0; line < sourceCodeArr.length; line++) {
		let lineText = sourceCodeArr[line];
		let prevLineWasEmpty = trimmedLineText === "";
		trimmedLineText = lineText.trim();
		if (endToken !== undefined) {
			if (insideBlockComment || insideDocComment) {
				if (lineText.indexOf("/*") >= 0)
					commentDepth++;
			}

			let match = lineText.match(endToken);
			if (match !== null || line === sourceCodeArr.length - 1) {
				const eol = 99999;

				let endLine = (insideBlockComment || insideDocComment) ? line : line - 1;

				if (insideBlockComment) {
					commentDepth--;
					if (commentDepth > 0) continue;
					foldingRanges.push(new FoldingRange(startLine, endLine, FoldingRangeKind.Comment));
				}
				else if (insideDocComment) {
					commentDepth--;
					if (commentDepth > 0) continue;
					foldingRanges.push(new FoldingRange(startLine, endLine, FoldingRangeKind.Comment));
				}
				else { // herestring
					foldingRanges.push(new FoldingRange(startLine, endLine));
				}

				endToken = undefined;

				if (insideBlockComment) {
					insideBlockComment = false;
					continue;
				}

				let range = new Range(
					new Position(startLine, 0),
					new Position(endLine, eol)
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
						range = new Range(
							new Position(range.start.line + 1, 0),
							range.end
						);
					}
					if (range.end.character !== eol) {
						if (range.end.line - 1 < range.start.line) continue;
						range = new Range(
							range.start,
							new Position(range.end.line - 1, eol),
						);
					}

					let decoration = { range };
					decorationsArrays[decorationColor].push(decoration);
				}
			}
		}
		else {
			let handled = false;

			if (!insideDocComment && !insideBlockComment) {
				if (trimmedLineText.startsWith("#scope_")) {
					if (regionStart >= 0)
						foldingRanges.push(new FoldingRange(regionStart, line - 1, FoldingRangeKind.Region));
					regionStart = line;
					handled = true;
				}

				if (importStart >= 0) {
					if (trimmedLineText.indexOf("#import") === -1
					&& trimmedLineText.indexOf("#load") === -1
					&&  trimmedLineText !== "") {
						let lineIndex = line - 1;
						if (prevLineWasEmpty) lineIndex--;
						if (lineIndex > importStart)
							foldingRanges.push(new FoldingRange(importStart, lineIndex, FoldingRangeKind.Imports));
						importStart = -1;
					}
				}
				else if (trimmedLineText.indexOf("#import") >= 0
					|| trimmedLineText.indexOf("#load") >= 0) {
					importStart = line;
					handled = true;
				}

				if (commentStart >= 0) {
					if (!trimmedLineText.startsWith("//")
					&&  trimmedLineText !== "") {
						let lineIndex = line - 1;
						if (prevLineWasEmpty) lineIndex--;
						if (lineIndex > commentStart)
							foldingRanges.push(new FoldingRange(commentStart, lineIndex, FoldingRangeKind.Comment));
						commentStart = -1;
					}
				}
				else if (trimmedLineText.startsWith("//")) {
					commentStart = line;
					handled = true;
				}

				if (blockStart >= 0) {
					if (lineText.startsWith("}")) {
						if (line > blockStart + 1)
							foldingRanges.push(new FoldingRange(blockStart, line));
						blockStart = -1;
					}
				}
				else if (!lineText.startsWith(" ") && trimmedLineText.endsWith("{")) {
					blockStart = line;
					handled = true;
				}

				if (parenStart >= 0) {
					if (lineText.startsWith(")")) {
						if (line > parenStart + 1)
							foldingRanges.push(new FoldingRange(parenStart, line));
						parenStart = -1;
					}
				}
				else if (!lineText.startsWith(" ") && trimmedLineText.endsWith("(")) {
					parenStart = line;
					handled = true;
				}
			}

			if (handled) continue;

			let match = lineText.match(hereString);
			let isHereString = true;

			if ((match === null || match.index === undefined) && !trimmedLineText.endsWith("*/")) {
				match = lineText.match(docComment);
				isHereString = false;

				if (match === null || match.index === undefined) {
					match = lineText.match(blockComment);
					if (match && match.index !== undefined) {
						startLine = line;
						insideBlockComment = true;
						insideDocComment = false;
						commentDepth = 1;
						isHereString = false;
						endToken = "\\*\\/";
						continue;
					}
				}
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
					commentDepth = 1;
					matchedLanguage = "md";
					endToken = "\\*\\/";
				}

				decorationColor = defaultEmbedColor;
				for (let i = 0; i < supportedLanguages.length; i++) {
					let language = supportedLanguages[i][0] as string;
					let pattern  = supportedLanguages[i][1] as RegExp;
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

	let lastLine = sourceCodeArr.length - 1;
	if (sourceCodeArr[lastLine].trim() === "")
		lastLine--;

	if (regionStart >= 0 && regionStart < lastLine)
		foldingRanges.push(new FoldingRange(regionStart, lastLine, FoldingRangeKind.Region));

	if (importStart >= 0 && importStart < lastLine)
		foldingRanges.push(new FoldingRange(importStart, lastLine, FoldingRangeKind.Imports));

	if (commentStart >= 0 && commentStart < lastLine)
		foldingRanges.push(new FoldingRange(commentStart, lastLine, FoldingRangeKind.Comment));

	if (blockStart >= 0 && blockStart < lastLine)
		foldingRanges.push(new FoldingRange(blockStart, lastLine));

	if (parenStart >= 0 && parenStart < lastLine)
		foldingRanges.push(new FoldingRange(parenStart, lastLine));

	for (let color in decorationsArrays) {
		editor.setDecorations(embedDecorations[color], decorationsArrays[color]);
	}

	for (let color in embedDecorations) {
		if (!(color in decorationsArrays))
			editor.setDecorations(embedDecorations[color], []);
	}
}

function updateAsm(sourceCode: string) {
	let asmStart = /#asm\b.*{/;
	let asmEnd = "}";

	const sourceCodeArr = sourceCode.split('\n');

	let startLine = 0;
	let startChar = 0;
	let insideAsm = false;
	asmRanges = [];

	for (let line = 0; line < sourceCodeArr.length; line++) {
		let lineText = sourceCodeArr[line];
		if (insideAsm) {
			let match = lineText.match(asmEnd);

			if (match !== null || line === sourceCodeArr.length - 1) {
				let eol;
				if (match === null || match.index === undefined)
					eol = 99999;
				else
					eol = match.index + 1;
				let range = new Range(
					new Position(startLine, startChar),
					new Position(line, eol)
				);
				asmRanges.push(range);
				insideAsm = false;
			}
		}
		else {
			let match = lineText.match(asmStart);
			if (match === null || match.index === undefined) continue;
			let singleLineMatch = lineText.slice(match.index + match[0].length).match(asmEnd);
			if (singleLineMatch === null || singleLineMatch.index === undefined) {
				insideAsm = true;
				startLine = line;
				startChar = match.index + match[0].length;
			}
			else {
				let range = new Range(
					new Position(line, match.index + match[0].length),
					new Position(line, match.index + match[0].length + singleLineMatch.index + 1)
				);

				asmRanges.push(range);
			}
		}
	}
}


class JaiCompletionItemProvider implements CompletionItemProvider {
	public provideCompletionItems(document: TextDocument, position: Position,
								  token: CancellationToken, context: CompletionContext):
		Thenable<CompletionItem[]> {
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
					if (match === null) {
						if (asmCompletions.length === 0)
							asmCompletions = loadAsmCompletions();
						resolve(asmCompletions);
					}
					else
						reject();
					return;
				}
			}
			reject();
		});
    }
}


class JaiFoldingRangeProvider implements FoldingRangeProvider {
	public provideFoldingRanges(document: TextDocument): ProviderResult<FoldingRange[]> {
		return new Promise(resolve => {
			resolve(foldingRanges);
		});
	}
}


class JaiReferenceProvider implements ReferenceProvider {
	public provideReferences(document: TextDocument, position: Position,
							 options: { includeDeclaration: boolean }, token: CancellationToken):
	Thenable<Location[]> {
		return new Promise((resolve, reject) => {
			for (let i = 0; i < asmRanges.length; i++) {
				let range = asmRanges[i];
				if (range.contains(position)) {
					reject();
					return;
				}
			}

			if (debugMode) {
				console.log(foundSomeReferences);
				console.log(referenceByFilepath);
			}

			if (foundSomeReferences) {
				let locations = findLocations(document.getText(document.getWordRangeAtPosition(position, /[a-zA-Z_]\w*/)), document.uri, position);
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


class JaiDefinitionProvider implements DefinitionProvider {
	public provideDefinition(document: TextDocument, position: Position,
							 token: CancellationToken):
	ProviderResult<Definition | DefinitionLink[]> {
		return new Promise<Definition>((resolve, reject) => {
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
					let uri = Uri.file(m[1]);
					let posRow = parseInt(m[2]) - 1;
					let startPosition = new Position(posRow, 0);
					let endPosition = new Position(posRow, 0);
					let location = new Location(uri, new Range(startPosition, endPosition));
					let result : Location[] = [];
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
							if (asmCompletions.length === 0)
								asmCompletions = loadAsmCompletions();
							let url = asmURLs[word];
							if (url === undefined) {
								reject();
							}
							else {
								env.openExternal(Uri.parse(url));
								reject();
							}
						}
						return;
					}
				}

				if (foundSomeReferences) {
					let locations = findLocations(document.getText(document.getWordRangeAtPosition(position, /[a-zA-Z_]\w*/)), document.uri, position);
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


class JaiRenameProvider implements RenameProvider {
	public provideRenameEdits(document: TextDocument, position: Position, newName: string,
							  token: CancellationToken):
	Thenable<WorkspaceEdit> {
		return new Promise<WorkspaceEdit>((resolve, reject) => {
			jaiLocate(document.fileName, position, "Rename").then(output => {
				if (output === undefined) {
					reject();
				}
				else {
					let locations = locationsFromString(output);
					let result = new WorkspaceEdit();
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


async function jaiLocate(filepath: string, position: Position, operation: string): Promise<string | undefined> {
	if (!useCompiler) return;

	let config = workspace.getConfiguration('the-language');
	let exe_path = config.get("pathToJaiExecutable");
	if (exe_path === undefined) return;

	if (debugMode) console.log("projectPath is [" + projectPath + "]");
	let fileToCompile = projectPath !== "" ? projectPath as string : filepath;

	let extension = extensions.getExtension("onelivesleft.the-language");
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

	if (debugMode) logCommand(exe_path as string, args);

	return execCommand(exe_path as string, args);
}


async function jaiDump(filepath: string): Promise<[string, string] | undefined> {
	if (!useCompiler) return;

	let config = workspace.getConfiguration('the-language');
	let exe_path = config.get("pathToJaiExecutable");
	if (exe_path === undefined) return;

	if (debugMode) console.log("projectPath is [" + projectPath + "]");
	let fileToCompile = projectPath !== "" ? projectPath as string : filepath;

	let extension = extensions.getExtension("onelivesleft.the-language");
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

	if (debugMode) logCommand(exe_path as string, args);

	return spawnCommand(exe_path as string, args);
}

function logCommand(command: string, args: string[]) {
	let commandLine = [command];
	for(let i = 0; i < args.length; i++) {
		if (args[i].match(/ /)) {
			commandLine.push("\"" + args[i] + "\"");
		}
		else
			commandLine.push(args[i]);
	}
	console.log(commandLine.join(" "));
}


function execCommand(exe_path: string, args: string[]): Promise<string | undefined> {
	return new Promise((resolve, reject) => {
		proc.execFile(exe_path, args, (error, stdout, stderr) => {
			if (error) { // @TODO does a warning trigger this?
				console.log(error);
				console.log(stderr);
				reject(error);
			}
			else {
				if (debugMode) console.log(stdout.substring(0, 256));
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

function spawnCommand(exe_path: string, args: string[]): Promise<[string, string] | undefined> {
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
				if (debugMode) console.log(errors.join("").substring(0, 256), stdout.substring(0, 256));
				let index = stdout.indexOf(sentinel);
				if (index < 0)
					reject(errors.join("") + "\n" + stdout);
				else
					resolve([stdout.slice(index + sentinel.length), errors.join("")]);
			}
		});
	});
}


function locationsFromString(locations: string, firstLineOnly: boolean = false): Location[] {
	//console.log(locations);
	let result : Location[] = [];
	for (let row of locations.split("\n")) {
		if (!row.trim()) continue;
		let items = row.split("|");
		let uri = Uri.file(items[1]);
		let startPosition = new Position(parseInt(items[2]) - 1, parseInt(items[3]) - 1);
		let endPosition = new Position(parseInt(items[4]) - 1, parseInt(items[5]) - 1);
		let location = new Location(uri, new Range(startPosition, endPosition));
		result.push(location);
		if (firstLineOnly) break;
	}

	return result;
}


function findLocations(name: string, uri: Uri, position: Position): Location[] {
	let fileReferences = referenceByFilepath[uri.fsPath.toLowerCase()];
	if (!fileReferences) return [];

	let closestDistance = 999999;
	let closestLocations : Location [] = [];

	for (let i = 0; i < fileReferences.length; i++) {
		let reference = fileReferences[i];
		if (reference.name === name) {
			for (let l = 0; l < reference.locations.length; l++) {
				let location = reference.locations[l];
				if (location.range.contains(position))
					return reference.locations;
				else {
					let d = distanceFromLocation(position, location);
					if (d < closestDistance) {
						closestDistance = d;
						closestLocations = reference.locations;
					}
				}
			}
		}
	}

	return closestLocations;
}


function distanceFromLocation(position: Position, location: Location): number {
	if (position.isBefore(location.range.start))
		return (location.range.start.line - position.line) * 100 + location.range.start.character - position.character;
	else
		return (position.line - location.range.end.line) * 100 + position.character - location.range.end.character;
}


function min(a: number, b: number): number {
	if (a <= b) return a; else return b;
}
