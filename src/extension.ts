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


export function activate(context: vscode.ExtensionContext) {


	let disposable = vscode.commands.registerCommand('the-language.test', () => {
		jai([
			"c:/repos/jai-cookbook/tools/locate.jai",
			"--",
			"c:/repos/jaitest/foo.jai",
			"c:/repos/jaitest/foo.jai",
			"213", "5",
		]).then(output => {
			if (output === undefined)  return;
			console.log(output);
		});
	});

	context.subscriptions.push(disposable);
}

export function deactivate() {}


async function jai(args: string[]): Promise<string | undefined> {
	let config = vscode.workspace.getConfiguration('the-language');
	let exe_path = config.get("pathToJaiExecutable");
	if (exe_path === undefined) return;

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
