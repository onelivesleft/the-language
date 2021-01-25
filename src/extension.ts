/* eslint-disable @typescript-eslint/naming-convention */
/* eslint-disable curly */
// TODO:
// [ ] Goto definition
// [ ] Find All References
// [ ] Rename
// [ ] Show current proc in status bar
// [ ] Show #dump of current proc
// [ ] Goto next error


import * as vscode from 'vscode';
import proc = require('child_process');
import path = require('path');
import fs = require('fs');
import { start } from 'repl';

const SELECTOR: vscode.DocumentFilter = { language: 'jai', scheme: 'file' };


export function activate(context: vscode.ExtensionContext) {
	context.subscriptions.push(vscode.languages.registerReferenceProvider(SELECTOR, new JaiReferenceProvider()));
	context.subscriptions.push(vscode.languages.registerDefinitionProvider(SELECTOR, new JaiDefinitionProvider()));
	context.subscriptions.push(vscode.languages.registerRenameProvider(SELECTOR, new JaiRenameProvider()));
}

export function deactivate() {}


class JaiReferenceProvider implements vscode.ReferenceProvider {
	public provideReferences(document: vscode.TextDocument, position: vscode.Position,
							 options: { includeDeclaration: boolean }, token: vscode.CancellationToken):
	Thenable<vscode.Location[]> {
		return new Promise((resolve, reject) => {
			jaiLocate(document.fileName, position).then(output => {
				if (output === undefined) {
					reject();
				}
				else {
					let locations = locationsFromString(output);
					resolve(locations);
				}
			});
		});
    }
}


class JaiDefinitionProvider implements vscode.DefinitionProvider {
	public provideDefinition(document: vscode.TextDocument, position: vscode.Position,
							 token: vscode.CancellationToken):
	vscode.ProviderResult<vscode.Definition | vscode.DefinitionLink[]> {
		return new Promise<vscode.Definition>((resolve, reject) => {
			jaiLocate(document.fileName, position).then(output => {
				if (output === undefined) {
					reject();
				}
				else {
					let locations = locationsFromString(output, true);
					resolve(locations[0]);
				}
			});
		});
	}
}


class JaiRenameProvider implements vscode.RenameProvider {
	public provideRenameEdits(document: vscode.TextDocument, position: vscode.Position, newName: string,
							  token: vscode.CancellationToken):
	Thenable<vscode.WorkspaceEdit> {
		return new Promise<vscode.WorkspaceEdit>((resolve, reject) => {
			jaiLocate(document.fileName, position).then(output => {
				if (output === undefined) {
					reject();
				}
				else {
					let locations = locationsFromString(output);
					let result = new vscode.WorkspaceEdit();
					for (let i = 0; i < locations.length; i++) {
						let location = locations[i];
						console.log(location.uri.fsPath);
						result.replace(location.uri, location.range, newName);
					}
					console.log(result);
					resolve(result);
				}
			});
		});
	}
}


async function jaiLocate(filepath: string, position: vscode.Position): Promise<string | undefined> {
	let config = vscode.workspace.getConfiguration('the-language');
	let exe_path = config.get("pathToJaiExecutable");
	if (exe_path === undefined) return;

	let normalized = filepath.replace(/\\/g, '/');

	let args : string [] = [
		"c:/repos/jai-cookbook/tools/locate.jai",
		"--",
		normalized,
		normalized,
		(position.line + 1).toString(),
		(position.character + 1).toString()
	];

	return execCommand(exe_path as string, args);
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
				resolve(stdout);
			}
		});
	});
}


function locationsFromString(locations: string, firstLineOnly: boolean = false): vscode.Location[] {
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
