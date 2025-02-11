#lang scribble/manual

@require[@for-label[racket/base
                    racket/contract
                    xiden/cmdline
                    xiden/cli
                    xiden/cli-flag
                    xiden/format
                    xiden/l10n
                    xiden/state
                    xiden/subprogram
                    xiden/message
                    xiden/source]
          "../../shared.rkt"]

@title{Command Line Argument Parsers}

@defmodule[xiden/cli]

@racketmodname[xiden/cli] implements the command line parsers for
Xiden in terms of @racketmodname[xiden/cmdline]. Each parser
prepares a program that uses continuation passing style to return
output and an exit code.

@defproc[(launch-xiden! [#:arguments arguments (or/c list? vector?) (current-command-line-arguments)]
                        [#:format-message format-message message-formatter/c (get-message-formatter)]
                        [#:handle-exit handle-exit (-> any/c any) exit])
                        any]{
Returns @racket[(handle-exit status)], where @racket[status] depends
on program behavior caused as a side-effect.

The side-effect is to parse the given command line arguments, then
perform work described therein. Any @tech{messages} encountered are
printed to @racket[(current-output-port)] after being formatted by
@racket[format-message].
}


@defthing[top-level-cli argument-parser/c]{
Returns a @racket[bound-program/c] based on the first argument,
@racketid[subcommand], with consideration to command line flags that
apply to every possible subcommand. If @racketid[subcommand] is not
defined, then the program halts with exit code @racket[1] and output
@racket[($cli:undefined-command subcommand)].
}

@defthing[do-command argument-parser/c]{
Returns a @racket[bound-program/c] that carries out work defined in
@racket[args]. In the event no work is possible, then the program will
trivially halt with exit code 0 and produce no output.

Otherwise, the command will build a transaction where command-line
flags add work to execute in reading order.
}


@defthing[gc-command argument-parser/c]{
Returns a @racket[bound-program/c] that collects garbage in a
@tech{target workspace}.

Assuming no exceptional behavior, the bound program halts with exit code 0
with output @racket[($finished-collecting-garbage (xiden-collect-garbage))].
}


@defthing[show-command argument-parser/c]{
Returns a @racket[bound-program/c] with behavior based on the first
argument @racket[A].

If @racketid[A] is @racket{installed}, the program halts with exit
code 0 and output @racket[(list ($show-string S) ...)], where
@racket[S] is a string formatted to show a @tech{package query}, a
package output and a directory path. The list represents all installed
outputs in the @tech{target workspace}.

If @racketid[A] is @racket{log}, the program halts with exit code 0
and an empty program log. As a side-effect, the program prints all
data read from standard input using
@racket[(current-message-formatter)].  This is useful when one Xiden
user dumps a log to a file, and another wants to read the messages in
a different human language or notation.

If @racket{links}, the program halts with exit code 0 and output
@racket[(list ($show-string L) ...)], where @racket[L] is a string
containing a path to a symbolic link and a path to another filesystem
entry referenced by that link. These symbolic links are special in
that they are tracked by Xiden for garbage collection
purposes.

In all other cases, the program halts with exit code 1 and output
@racket[($cli:undefined-command A)].
}

@defthing[fetch-command argument-parser/c]{
Returns a @racket[bound-program/c] based on the first argument
@racketid[A].

@racketid[A] is treated as a string representation of a datum to
evaluate using @racket[eval-untrusted-source-expression]. If the
result is a @tech/xiden-reference{source} and the evaluation produced
no I/O (for security), then the command sents bytes produced from the
source to @racket[(current-output-port)]. Information about the
process is sent to @racket[(current-error-port)].

This all happens under a @tech{runtime configuration}, so transfers
can be halted by settings like @racket[XIDEN_FETCH_TOTAL_SIZE_MB].
}
