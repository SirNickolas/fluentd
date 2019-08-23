module asm_.grammar;

import pegged.grammar;

mixin(grammar(q"PEG
Assembly:

Program     <- ProgramLine* eoi

# We forbide tabs after non-tabs, so the only allowed spacing is ' '.
Spacing     <: ' '*

eol         <: '\r\n' / [\n\r] / eoi # Newline at EOF is optional.

WordEnd     <- ![-A-Za-z0-9_.@]
identifier  <~ [A-Za-z] [-A-Za-z0-9_]*
Number      <~ '-'? [0-9]+ ('.' [0-9]+)? ([Ee] [-+]? [0-9]+)?

Char        <~
    / '\\' ["\\nrt]
    / ![\t\n\r"\\] .

String      <~ :'\"' Char* :'\"'

PragmaExtern <- '.extern' WordEnd

ExternLine  < :PragmaExtern identifier :'[' identifier :']'

Public      <- '@'
Label       <-
    / Public identifier (:'.' identifier)?
    / identifier

LabelLine   < Label :':'

Instruction <~ identifier WordEnd

Argument    <-
    / Number
    / String
    / Label

CodeLine    < Instruction (Argument (:',' Argument)*)?

ProgramLine <-
    :'\t'* # Tabs are only allowed at the very start of a line.
    (
        / ExternLine
        / LabelLine
        / CodeLine
        / Spacing
    )
    # A comment.
    :(
        ';'
        [\t ;]* # For convinience, comments may also include tabs at their beginning.
        (![\t\n\r] .)*
    )?
    eol

PEG"));
