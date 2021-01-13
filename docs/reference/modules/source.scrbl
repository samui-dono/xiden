#lang scribble/manual

@require[@for-label[racket/base
                    racket/contract
                    xiden/cmdline
                    xiden/logged
                    xiden/port
                    xiden/rc
                    xiden/source
                    xiden/message
                    @except-in[xiden/pkgdef #%module-begin url]
                    xiden/printer
                    xiden/url]
                    "../../shared.rkt"]


@title{Data Sourcing}

@defmodule[xiden/source]

A @deftech{source} is a value that implements @racket[gen:source].
When used with @racket[fetch], a source produces an input port and an
estimate of how many bytes that port can produce. Xiden uses sources
to read data with safety limits. To @deftech{tap} a source means
gaining a reference to the input port and estimate. To
@deftech{exhaust} a source means gaining a reference to a contextual
error value. We can also say a source is @deftech{tapped} or
@deftech{exhausted}.

Note that these terms are linguistic conveniences. There is no value
representing a tapped or exhausted state. The only difference is where
control ends up in the program, and what references become available
as a result of using @racket[fetch] on a source.


@defthing[tap/c
  chaperone-contract?
  #:value
  (-> input-port?
      (or/c +inf.0 exact-positive-integer?)
      any/c)]{
A @tech/reference{contract} for a procedure used to @tech{tap} a
@tech{source}.

The procedure is given an input port, and an estimate of the maximum
number of bytes the port can produce. This estimate could be
@racket[+inf.0] to allow unlimited reading, provided the user allows
this in their configuration.
}

@defthing[exhaust/c chaperone-contract? #:value (-> any/c any/c)]{
A @tech/reference{contract} for a procedure used when a source is
@tech{exhausted}.

The sole argument to the procedure depends on the source type.
}

@deftogether[(
@defidform[gen:source]
@defthing[source? predicate/c]
@defproc[(fetch [source source?] [tap tap/c] [exhaust exhaust/c]) any/c]
)]{
@racket[gen:source] is a @tech/reference{generic interface} that
requires an implementation of @racket[fetch]. @racket[source?]
returns @racket[#t] for values that do so.

@racket[fetch] attempts to @tech{tap} @racket[source]. If successful,
@racket[fetch] calls @racket[tap] in tail position, passing the input
port and the estimated maximum number of bytes that port is expected
to produce.

Otherwise, @racket[fetch] calls @racket[exhaust] in tail position
using a source-dependent argument.
}


@deftogether[(
@defproc[(logged-fetch [source source?] [tap tap/c]) logged?]
@defstruct*[($fetch $message) ([errors (listof $message?)])]
)]{
Returns a @tech{logged procedure} that applies @racket[fetch] to
@racket[source] and @racket[tap].

The computed value of the logged procedure is @racket[FAILURE] if the
source is @tech{exhausted}. Otherwise, the value is what's returned
from @racket[tap].

The log will gain a @racket[($fetch errors)] message, where
@racketid[errors] is empty if the fetch is successful.
}


@section{Source Types}

@defstruct*[exhausted-source ([value any/c])]{
A source that is always @tech{exhausted}, meaning that
@racket[(fetch (exhausted-source v) void values)] returns @racket[v].
}


@defstruct*[byte-source ([data bytes?])]{
A source that, when @tech{tapped}, yields
bytes directly from @racket[data].
}

@defstruct*[first-available-source ([sources (listof sources?)] [errors list?])]{
A @tech{source} that, when @tech{tapped}, yields bytes from the first
tapped source.

If all sources for an instance are exhausted, then the instance is
exhausted.  As sources are visited, errors are functionally
accumulated in @racket[errors].

The value produced for an exhausted @racket[first-available-source] is
the longest possible list bound to @racket[errors].
}


@defstruct[text-source ([data string?])]{
A @tech{source} that, when @tech{tapped}, produces bytes from the given string.
}


@defstruct[lines-source ([suffix (or/c #f char? string?)] [lines (listof string?)])]{
A @tech{source} that, when @tech{tapped}, produces bytes from a
string.  The string is defined as the combination of all
@racket[lines], such that each line has the given @racket[suffix].  If
@racket[suffix] is @racket[#f], then it uses a conventional line
ending according to @racket[(system-type 'os)].

@racketblock[
(define src
  (lines-source "\r\n"
                '("#lang racket/base"
                  "(provide a)"
                  "(define a 1)")))

(code:comment "\"#lang racket/base\r\n(provide a)\r\n(define a 1)\r\n\"")
(fetch src consume void)
]
}


@defstruct[file-source ([path path-string?])]{
A @tech{source} that, when @tech{tapped}, yields bytes
from the file located at @racket[path].

If the source is @tech{exhausted}, it yields a relevant
@racket[exn:fail:filesystem] exception.
}


@defstruct[http-source ([request-url (or/c url? url-string?)])]{
A @tech{source} that, when @tech{tapped}, yields bytes from an HTTP
response body. The response comes from a GET request to
@racket[request-url], and the body is only used for a 2xx response.

If the source is @tech{exhausted}, it yields a relevant exception.

The behavior of the source is impacted by @racket[XIDEN_DOWNLOAD_MAX_REDIRECTS].
}


@defstruct[http-mirrors-source ([request-urls (listof (or/c url-string? url?))])]{
Like @racket[http-source], but tries each of the given URLs using
@racket[first-available-source].
}


@defstruct[plugin-source ([hint any/c] [kw-lst list?] [kw-val-lst list?] [list? lst])]{
A @tech{source} that consults the user's @tech{plugin} for data.

The plugin is responsible for using @racket[hint] and
@racket[fetch]-specific bindings to select a procedure. That procedure
is then applied (as in @racket[keyword-apply]), to the remaining
fields. The plugin then controls the result of the fetch.

Xiden binds @racket[hint] to @racket['coerced] when using
@racket[coerce-source].
}


@section{Source Expressions}

The following procedures are useful for declaring sources in a
@tech{package input}.

@defproc[(sources [variant (or/c string? source?)] ...) source?]{
Like @racket[first-available-source], but each string argument is
coerced to a source using @racket[coerce-source].
}

@defproc[(coerce-source [variant (or/c string? source?)]) source?]{
Returns @racket[variant] if it is already a @tech{source}.

Otherwise, returns
@racketblock[
(first-available-source
  (list (file-source s)
        (http-source s)
        (plugin-source 'coerced null null (list s)))
  null)]
}

@defproc[(from-catalogs [query-string string?] [url-templates (listof string?) (XIDEN_CATALOGS)]) (listof url-string?)]{
Returns a list of URL strings computed by URL-encoding
@racket[query-string], and then replacing all occurrances of
@racket{$QUERY} in @racket[url-templates] with the encoded string.
}

@defform[(from-file relative-path-expr)]{
Expands to a complete path. @racket[relative-path-expr] is a relative path
made complete with regards to the source directory in which this expression
appears.

Due to this behavior, @racket[from-file] will return different results when the
containing source file changes location on disk.
}


@section{Transferring Bytes}

@defmodule[xiden/port]

@racketmodname[xiden/port] reprovides all bindings from
@racketmodname[racket/port], in addition to the bindings defined in
this section.

@defproc[(mebibytes->bytes [mebibytes real?]) exact-nonnegative-integer?]{
Converts mebibytes to bytes, rounded up to the nearest exact integer.
}

@defproc[(transfer [bytes-source input-port?]
                   [bytes-sink output-port?]
                   [#:on-status on-status (-> $transfer? any)]
                   [#:max-size max-size (or/c +inf.0 exact-positive-integer?)]
                   [#:buffer-size buffer-size exact-positive-integer?]
                   [#:transfer-name transfer-name non-empty-string?]
                   [#:est-size est-size (or/c +inf.0 real?)]
                   [#:timeout-ms timeout-ms (>=/c 0)])
                   void?]{
Like @racket[copy-port], except bytes are copied from
@racket[bytes-source] to @racket[bytes-sink], with at most
@racket[buffer-size] bytes at a time.

@racket[transfer] applies @racket[on-status] repeatedly and
synchronously with @racket[$transfer] @tech{messages}.

@racket[transfer] reads no more than @racketid[N] bytes from
@racket[bytes-source], and will wait no longer than
@racket[timeout-ms] for the next available byte.

The value of @racketid[N] is computed using @racket[est-size] and
@racket[max-size]. @racket[max-size] is the prescribed upper limit for
total bytes to copy. @racket[est-size] is an estimated for the number
of bytes that @racket[bytes-source] will actually produce (this is
typically not decided by the user). If @racket[(> est-size max-size)],
then the transfer will not start.  Otherwise @racketid[N] is bound to
@racket[est-size] to hold @racket[bytes-source] accountable for the
estimate.

If @racket[est-size] and @racket[max-size] are both @racket[+inf.0],
then @racket[transfer] will not terminate if @racket[bytes-source]
does not produce @racket[eof].
}


@defstruct*[($transfer $message) () #:prefab]{
A @tech{message} pertaining to a @racket[transfer] status.
}

@defstruct*[($transfer:scope $transfer) ([name string?] [message (and/c $transfer? (not/c $transfer:scope?))]) #:prefab]{
Contains a @racket[$transfer] message from a call to @racket[transfer]
where the @racketid[transfer-name] argument was bound to
@racket[name].
}

@defstruct*[($transfer:progress $transfer) ([bytes-read exact-nonnegative-integer?]
                                            [max-size (or/c +inf.0 exact-positive-integer?)]
                                            [timestamp exact-positive-integer?]) #:prefab]{
Represents progress transferring bytes to a local source.

Unless @racket[max-size] is @racket[+inf.0], @racket[(/ bytes-read
max-size)] approaches @racket[1].  You can use this along with the
@racket[timestamp] (in seconds) to reactively compute an estimated
time to complete.
}


@defstruct*[($transfer:budget $transfer) () #:prefab]{
A message pertaining to a transfer space budget.
}


@defstruct*[($transfer:budget:exceeded $message) ([size exact-positive-integer?]) #:prefab]{
A request to transfer bytes was halted because the transfer read
@racket[overrun-size] bytes more than @racket[allowed-max-size] bytes.

See @racket[XIDEN_FETCH_TOTAL_SIZE_MB] and @racket[XIDEN_FETCH_PKGDEF_SIZE_MB].
}


@defstruct*[($transfer:budget:rejected $message) ([proposed-max-size (or/c +inf.0 exact-positive-integer?)]
                                                  [allowed-max-size exact-positive-integer?]) #:prefab]{
A request to transfer bytes never started because the transfer estimated
@racket[proposed-max-size] bytes, which exceeds the user's maximum of @racket[allowed-max-size].

See @racket[XIDEN_FETCH_TOTAL_SIZE_MB] and @racket[XIDEN_FETCH_PKGDEF_SIZE_MB].
}



@defstruct*[($transfer:timeout $message) ([bytes-read exact-nonnegative-integer?] [wait-time (>=/c 0)]) #:prefab]{
A request to transfer bytes was halted after @racket[bytes-read] bytes
because no more bytes were available after @racket[wait-time]
milliseconds.

See @racket[XIDEN_FETCH_TIMEOUT_MS].
}
