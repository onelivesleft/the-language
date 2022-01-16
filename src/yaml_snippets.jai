// @Note bare-bones YAML parsing, so 2-space indents only!

markdown_block_comments_header :: #string ___yaml
  markdown-block-comments:
    name: meta.embedded.block.markdown
    begin: (\s*\/\*\*)
    end: (\s*\*\/)
    beginCaptures:
      1:
        name: punctuation.definition.comment.jai
    endCaptures:
      1:
        name: punctuation.definition.comment.jai
    patterns:
      - include: '#block-comments'
___yaml

markdown_block_comments_language :: #string yaml
      - begin: ((?i)```%1)
        end: (```)
        beginCaptures:
          1:
            name: markup.quote.code.comment.%2.jai
        endCaptures:
          1:
            name: markup.quote.code.comment.%2.jai
        patterns:
          - include: %3
yaml

markdown_block_comments_footer :: #string yaml
      - begin: (```)
        end: (```)
        beginCaptures:
          1:
            name: markup.quote.code.comment.jai
        endCaptures:
          1:
            name: markup.quote.code.comment.jai
        patterns:
          - include: source.jai
      - contentName: meta.embedded.block.markdown
        include: text.html.markdown
yaml


strings_header :: #string ___yaml
  strings:
    patterns:
      - name: string.quoted.double.empty.jai
        match: (")(")
        captures:
          1:
            name: punctuation.definition.string.empty.begin.jai
          2:
            name: punctuation.definition.string.empty.end.jai
      - name: string.quoted.double.jai
        begin: (")
        end: ("|$)
        beginCaptures:
          1:
            name: punctuation.definition.string.begin.jai
        endCaptures:
          1:
            name: punctuation.definition.string.end.jai
        patterns:
          - name: constant.character.escape.jai
            match: \\.
          - name: constant.other.placeholder.jai
            match: %[0-9]+
          - match: (%)%
            captures:
              '1':
                name: constant.character.escape.jai
          - name: constant.other.placeholder.jai
            match: %
___yaml

strings_language :: #string ___yaml
      - name: string.here.embed.%2.jai
        begin: (#string)\s+((?i)([A-Za-z_]\w*)?(%1))\b
        end: \s*(\3)(\4)
        beginCaptures:
          1:
            name: keyword.other.directive.string.%2.jai
          2:
            name: constant.other.stringdelimiter.here.embed.%2.jai
          4:
            name: constant.other.stringdelimiter.here.embed.language.%2.jai
        endCaptures:
          1:
            name: constant.other.stringdelimiter.here.embed.%2.jai
          2:
            name: constant.other.stringdelimiter.here.embed.language.%2.jai
        contentName: string.unquoted.here.embed.%2.jai
        patterns:
          - include: %3
___yaml

strings_footer :: #string ___yaml
      - name: string.here.jai
        begin: (#string)\s+([A-Za-z_]\w*)
        end: \s*(\2)
        beginCaptures:
          1:
            name: keyword.other.directive.string.jai
          2:
            name: constant.other.stringdelimiter.here.jai
        endCaptures:
          1:
            name: constant.other.stringdelimiter.here.jai
        contentName: string.unquoted.here.jai
___yaml

deprecated_names_insert :: #string __yaml
  deprecated-names:
    name: invalid.deprecated.jai
    match: \b(%)\b
__yaml

support_names_insert :: #string __yaml
  support:
    patterns:
      - name: support.function.jai
        match: \b(align_of|code_of|type_of|size_of|type_info|initializer_of)\b
      - name: support.function.jai
        match: \b(%)\b
      - name: support.class.jai
        match: \b(%)\b
__yaml
