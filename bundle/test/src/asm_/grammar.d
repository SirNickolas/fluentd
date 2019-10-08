module asm_.grammar;

import pegged.grammar;

mixin(grammar(q"PEG
Assembly:

Program     <- ProgramLine* eoi

# We forbid tabs in the source.
Spacing     <: ' '*

eol         <: '\r\n' / [\n\r] / eoi # Newline at EOF is optional.

WordEnd     <- ![-A-Za-z0-9_.@]
identifier  <~ [A-Za-z] [-A-Za-z0-9_]*
Number      <~ '-'? [0-9]+ ('.' [0-9]+)? ([Ee] [-+]? [0-9]+)?

Char        <~
    / '\\' . # Allowed escape sequences are \", \\, \n, \r, and \t.
    / ![\t\n\r"\\] .

String      <~ :'\"' Char* :'\"'

PragmaExtern <- '.extern' WordEnd

ExternLine  < :PragmaExtern identifier

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
    (
        / ExternLine
        / LabelLine
        / CodeLine
        / Spacing
    )
    # A comment.
    :(';' (![\t\n\r] .)*)?
    eol

PEG"));
