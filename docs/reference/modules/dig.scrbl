#lang scribble/manual

@require["../../shared.rkt"
         @for-label[racket/base
                    racket/contract
                    racket/match
                    racket/string
                    xiden/artifact
                    xiden/dig
                    xiden/input
                    xiden/subprogram
                    xiden/message
                    xiden/package
                    xiden/query
                    xiden/source
                    xiden/string
                    xiden/url
                    xiden/version]]

@title{Digs}

@defmodule[xiden/dig]

The @deftech{digsite metaphor} states that a process must use a
@deftech{shovel} to @deftech{dig} for @tech{artifacts}. Despite
putting the same amount of effort into each scoop, what the shovel
impacts and yields may change.

In Racket, a shovel is a @racket[shovel/c] procedure and a dig is
underway when such a procedure has program control.

The digsite metaphor implies some level of repeated effort (digging)
towards uncertain results. For example, the built-in shovels for
@racketmodname[xiden/dig/filesystem] resolve symbolic links as a way
to “scoop” towards a possibly non-existent file. In a similar
scenario, a server hosting data may respond differently to the same
request, or issue redirects a shovel may follow.


@defstruct*[($dig $message) ()]{
A @tech{message} regarding the results of a @tech{dig}.
}


@defstruct*[($dig:no-artifact $dig) ([shovel-name (or/c string? symbol?)] [hint any/c])]{
Represents a failure to find an artifact using a shovel identified by
@racket[shovel-name]. The @racket[hint] is @racket[eq?] to the
argument used for the shovel.
}


@defthing[shovel/c chaperone-contract?
                   #:value (-> any/c (subprogram/c artifact-info?))]{
A @tech/reference{chaperone contract} for procedures that carry out
@tech{digs}. They must return @tech{subprograms} to capture
possible @tech{messages} for failure conditions.
}


@defproc[(find-artifact [hint any/c]
                        [shovel shovel/c (current-shovel)])
                        (subprogram/c artifact-info?)]{
Returns a @tech{subprogram} used to find an @tech{artifact} with
the given @tech{shovel}.

If @racket[hint] is already an @tech{artifact}, then it will be
returned as-is. Otherwise, the result depends on the implementation of
the @tech{shovel}.
}


@defthing[current-shovel (parameter/c shovel/c)]{
This procedure controls how non-artifact values used in
@racket[package-input-plinth] become @tech{artifacts}.

The default value is @racket[broken-shovel].
}


@defthing[broken-shovel shovel/c]{
A shovel that cannot dig. It unconditionally fails and adds
a @racket[$dig:no-artifact] to the @tech{subprogram log}.
}

@defproc[(dig-failure [shovel-name (or/c string? symbol?)] [hint any/c]) subprogram?]{
Returns a @tech{subprogram} that unconditionally fails, adding
@racket[($dig:no-artifact shovel-name hint)] to the @tech{subprogram
log}.
}

@defproc[(shovel-cons [first shovel/c] [second shovel/c]) shovel/c]{
Returns a @tech{shovel} that tries using the first shovel,
then the second if the first fails to produce an artifact.
}

@defproc[(shovel-list [shovel shovel/c] ...) shovel/c]{
Returns a @tech{shovel} that tries each of the provided shovels in
order, implicitly ending with @racket[broken-shovel].
}

@include-section{dig/memory.scrbl}
@include-section{dig/filesystem.scrbl}
@include-section{dig/http.scrbl}
