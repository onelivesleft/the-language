'use strict';
import * as vscode from 'vscode';
import { commands, TextEditor, TextEditorEdit, Uri, ViewColumn } from 'vscode';
import * as path from 'path';
import * as fs from 'fs';


const BOTH = 0;
const UP   = 1;
const DOWN = 2;


export function activate(context: vscode.ExtensionContext) {

  let blockMultiCursor = new BlockMultiCursor();

  let growUp = vscode.commands.registerTextEditorCommand('blockMultiCursor.growUp', (editor: TextEditor, edit: TextEditorEdit) => {
    blockMultiCursor.grow(UP, editor, edit);
  });

  let growDown = vscode.commands.registerTextEditorCommand('blockMultiCursor.growDown', (editor: TextEditor, edit: TextEditorEdit) => {
    blockMultiCursor.grow(DOWN, editor, edit);
  });

  let grow = vscode.commands.registerTextEditorCommand('blockMultiCursor.grow', (editor: TextEditor, edit: TextEditorEdit) => {
    blockMultiCursor.grow(BOTH, editor, edit);
  });


  context.subscriptions.push(growUp);
  context.subscriptions.push(growDown);
  context.subscriptions.push(grow);
}


export function deactivate() {
}


class BlockMultiCursor {
  async grow(direction: number, editor: TextEditor, edit: TextEditorEdit) {
    let sortedSelections = editor.selections.sort((a, b) => (a.end.line - b.end.line));

    if (direction === BOTH || direction === UP) {
      let cursor = sortedSelections[0];
      let column = cursor.end.character;
      let startLine = cursor.end.line - 1;
      if (startLine > 0 && direction === UP) {
        let lineText = editor.document.lineAt(startLine).text;
        while (startLine > 0 && lineText.length < column) {
          startLine--;
          lineText = editor.document.lineAt(startLine).text;
        }
      }
      for (let line = startLine; line > 0; line--) {
        let lineText = editor.document.lineAt(line).text;
        if (lineText.length < column) break;

        editor.selections.push(new vscode.Selection(line, column, line, column));
      }
    }

    if (direction === BOTH || direction === DOWN) {
      let cursor = sortedSelections[sortedSelections.length - 1];
      let column = cursor.end.character;
      let startLine = cursor.end.line + 1;
      if (startLine < editor.document.lineCount && direction === DOWN) {
        let lineText = editor.document.lineAt(startLine).text;
        while (startLine < editor.document.lineCount - 1 && lineText.length < column) {
          startLine++;
          lineText = editor.document.lineAt(startLine).text;
        }
      }
      for (let line = startLine; line < editor.document.lineCount; line++) {
        let lineText = editor.document.lineAt(line).text;
        if (lineText.length < column) break;

        editor.selections.push(new vscode.Selection(line, column, line, column));
      }
    }

    editor.selections = editor.selections;
  }
}
