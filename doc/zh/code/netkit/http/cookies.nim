## This module provides the ``Cookie`` type, which directly maps to Set-Cookie HTTP response headers, 
## and the ``CookieJar`` type which contains many cookies.
## 
## Overview
## ========================
## 
## ``Cookie`` type is used to generate Set-Cookie HTTP response headers. 
## Server sends Set-Cookie HTTP response headers to the user agent.
## So the user agent can send them back to the server later.
## 
## ``CookieJar`` contains many cookies from the user agent.
## 


import options, times, strtabs, parseutils, strutils


type
  SameSite* {.pure.} = enum ## The SameSite cookie attribute.
    None, Lax, Strict

  Cookie* = object ## Cookie type represents Set-Cookie HTTP response headers.
    name*, value*: string
    expires*: string
    maxAge*: Option[int]
    domain*: string
    path*: string
    secure*: bool
    httpOnly*: bool
    sameSite*: SameSite

  CookieJar* = object ## CookieJar type is a collection of cookies.
    data: StringTableRef

  MissingValueError* = object of ValueError ## Indicates an error associated with Cookie.


proc initCookie*(name, value: string, expires = "", maxAge: Option[int] = none(int), 
                 domain = "", path = "",
                 secure = false, httpOnly = false, sameSite = Lax): Cookie {.inline.} =
  ## Initiates Cookie object.
  runnableExamples:
    let
      username = "admin"
      message = "ok"
      cookie = initCookie(username, message)
    
    doAssert cookie.name == username
    doAssert cookie.value == message

  result = Cookie(name: name, value: value, expires: expires, 
                  maxAge: maxAge, domain: domain, path: path,
                  secure: secure, httpOnly: httpOnly, sameSite: sameSite)
  
proc initCookie*(name, value: string, expires: DateTime|Time, 
                 maxAge: Option[int] = none(int), domain = "", path = "", secure = false, httpOnly = false,
                 sameSite = Lax): Cookie {.inline.} =
  ## Initiates Cookie object.
  runnableExamples:
    import times


    let
      username = "admin"
      message = "ok"
      expires = now()
      cookie = initCookie(username, message, expires)
    
    doAssert cookie.name == username
    doAssert cookie.value == message

  result = initCookie(name, value, format(expires.utc,
                      "ddd',' dd MMM yyyy HH:mm:ss 'GMT'"), maxAge, domain, path, secure,
                      httpOnly, sameSite)

proc parseParams(cookie: var Cookie, key: string, value: string) {.inline.} =
  ## Parse Cookie attributes from key-value pairs.
  case key.toLowerAscii
  of "expires":
    if value.len != 0:
      cookie.expires = value
  of "maxage":
    try:
      cookie.maxAge = some(parseInt(value))
    except ValueError:
      cookie.maxAge = none(int)
  of "domain":
    if value.len != 0:
      cookie.domain = value
  of "path":
    if value.len != 0:
      cookie.path = value
  of "secure":
    cookie.secure = true
  of "httponly":
    cookie.httpOnly = true
  of "samesite":
    case value.toLowerAscii
    of "none":
      cookie.sameSite = None
    of "strict":
      cookie.sameSite = Strict
    else:
      cookie.sameSite = Lax
  else:
    discard

proc initCookie*(text: string): Cookie {.inline.} =
  ## Initiates Cookie object from strings.
  runnableExamples:
    doAssert initCookie("foo=bar=baz").name == "foo"
    doAssert initCookie("foo=bar=baz").value == "bar=baz"
    doAssert initCookie("foo=bar; HttpOnly").httpOnly

  var 
    pos = 0
    params: string
    name, value: string
    first = true
  
  while true:
    pos += skipWhile(text, {' ', '\t'}, pos)
    pos += parseUntil(text, params, ';', pos)

    var start = 0
    start += parseUntil(params, name, '=', start)
    inc(start) # skip '='
    if start < params.len:
      value = params[start .. ^1]
    else:
      value = ""

    if first:
      if name.len == 0:
        raise newException(MissingValueError, "cookie name is missing!")
      if value.len == 0:
        raise newException(MissingValueError, "cookie valie is missing!")
      result.name = name
      result.value = value
      first = false
    else:
      parseParams(result, name, value)
    if pos >= text.len:
      break
    inc(pos) # skip ';

proc setCookie*(cookie: Cookie): string =
  ## Stringifys Cookie object to get Set-Cookie HTTP response headers.
  runnableExamples:
    import strformat


    let
      username = "admin"
      message = "ok"
      cookie = initCookie(username, message)

    doAssert setCookie(cookie) == fmt"{username}={message}; SameSite=Lax"

  result.add cookie.name & "=" & cookie.value
  if cookie.domain.strip.len != 0:
    result.add("; Domain=" & cookie.domain)
  if cookie.path.strip.len != 0:
    result.add("; Path=" & cookie.path)
  if cookie.maxAge.isSome:
    result.add("; Max-Age=" & $cookie.maxAge.get())
  if cookie.expires.strip.len != 0:
    result.add("; Expires=" & cookie.expires)
  if cookie.secure:
    result.add("; Secure")
  if cookie.httpOnly:
    result.add("; HttpOnly")
  if cookie.sameSite != None:
    result.add("; SameSite=" & $cookie.sameSite)

proc `$`*(cookie: Cookie): string {.inline.} = 
  ## Stringifys Cookie object to get Set-Cookie HTTP response headers.
  runnableExamples:
    import strformat


    let
      username = "admin"
      message = "ok"
      cookie = initCookie(username, message)

    doAssert $cookie == fmt"{username}={message}; SameSite=Lax"

  setCookie(cookie)

proc initCookieJar*(): CookieJar {.inline.} =
  ## Creates a new cookieJar that is empty.
  CookieJar(data: newStringTable(mode = modeCaseSensitive))

proc len*(cookieJar: CookieJar): int {.inline.} =
  ## Returns the number of names in ``cookieJar``.
  cookieJar.data.len

proc `[]`*(cookieJar: CookieJar, name: string): string {.inline.} =
  ## Retrieves the value at ``cookieJar[name]``.
  ##
  ## If ``name`` is not in ``cookieJar``, the ``KeyError`` exception is raised.
  cookieJar.data[name]

proc getOrDefault*(cookieJar: CookieJar, name: string, default = ""): string {.inline.} =
  ## Retrieves the value at ``cookieJar[name]`` if ``name`` is in ``cookieJar``. Otherwise, the
  ## default value is returned(default is "").
  cookieJar.data.getOrDefault(name, default)

proc hasKey*(cookieJar: CookieJar, name: string): bool {.inline.} =
  ## Returns true if ``name`` is in the ``cookieJar``.
  cookieJar.data.hasKey(name)

proc contains*(cookieJar: CookieJar, name: string): bool {.inline.} =
  ## Returns true if ``name`` is in the ``cookieJar``.
  ## Alias of ``hasKey`` for use with the ``in`` operator.
  cookieJar.data.contains(name)

proc `[]=`*(cookieJar: var CookieJar, name: string, value: string) {.inline.} =
  ## Inserts a ``(name, value)`` pair into ``cookieJar``.
  cookieJar.data[name] = value

proc parse*(cookieJar: var CookieJar, text: string) {.inline.} =
  ## Parses CookieJar from strings.
  runnableExamples:
    var cookieJar = initCookieJar()
    cookieJar.parse("username=netkit; message=ok")

    doAssert cookieJar["username"] == "netkit"
    doAssert cookieJar["message"] == "ok"

  var 
    pos = 0
    name, value: string
  while true:
    pos += skipWhile(text, {' ', '\t'}, pos)
    pos += parseUntil(text, name, '=', pos)
    if pos >= text.len:
      break
    inc(pos) # skip '='
    pos += parseUntil(text, value, ';', pos)
    cookieJar[name] = move(value)
    if pos >= text.len:
      break
    inc(pos) # skip ';'

iterator pairs*(cookieJar: CookieJar): tuple[name, value: string] =
  ## Iterates over any ``(name, value)`` pair in the ``cookieJar``.
  for (name, value) in cookieJar.data.pairs:
    yield (name, value)

iterator keys*(cookieJar: CookieJar): string =
  ## Iterates over any ``name`` in the ``cookieJar``.
  for name in cookieJar.data.keys:
    yield name

iterator values*(cookieJar: CookieJar): string =
  ## Iterates over any ``value`` in the ``cookieJar``.
  for value in cookieJar.data.values:
    yield value
