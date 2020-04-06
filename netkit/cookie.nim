import options, times, strtabs, parseutils


type
  SameSite* {.pure.} = enum
    None, Lax, Strict

  Cookie* = object
    name*, value*: string
    expires*: string
    maxAge*: Option[int]
    domain*: string
    path*: string
    secure*: bool
    httpOnly*: bool
    sameSite*: SameSite

  CookieJar* = object
    data: StringTableRef


proc initCookie*(name, value: string, expires = "", maxAge: Option[int] = none(int), 
                domain = "", path = "",
                 secure = false, httpOnly = false, sameSite = Lax): Cookie {.inline.} =
  result = Cookie(name: name, value: value, expires: expires, 
           maxAge: maxAge, domain: domain, path: path,
           secure: secure, httpOnly: httpOnly, sameSite: sameSite)
  
proc initCookie*(name, value: string, expires: DateTime|Time, 
    maxAge: Option[int] = none(int), domain = "", path = "", secure = false, httpOnly = false,
    sameSite = Lax): Cookie {.inline.} =
  result = initCookie(name, value, format(expires.utc,
           "ddd',' dd MMM yyyy HH:mm:ss 'GMT'"), maxAge, domain, path, secure,
           httpOnly, sameSite)

proc setCookie*(cookie: Cookie): string =
  result.add cookie.name & "=" & cookie.value
  if cookie.domain.len != 0:
    result.add("; Domain=" & cookie.domain)
  if cookie.path.len != 0:
    result.add("; Path=" & cookie.path)
  if cookie.maxAge.isSome:
    result.add("; Max-Age=" & $cookie.maxAge.get())
  if cookie.expires.len != 0:
    result.add("; Expires=" & cookie.expires)
  if cookie.secure:
    result.add("; Secure")
  if cookie.httpOnly:
    result.add("; HttpOnly")
  if cookie.sameSite != None:
    result.add("; SameSite=" & $cookie.sameSite)

proc `$`*(cookie: Cookie): string {.inline.} = 
  setCookie(cookie)

proc initCookieJar*(): CookieJar {.inline.} =
  CookieJar(data: newStringTable(mode = modeCaseSensitive))

proc len*(cookieJar: CookieJar): int {.inline.} =
  cookieJar.data.len

proc `[]`*(cookieJar: CookieJar, name: string): string {.inline.} =
  cookieJar.data[name]

proc getOrDefault*(cookieJar: CookieJar, name: string, default = ""): string {.inline.} =
  cookieJar.data.getOrDefault(name, default)

proc hasKey*(cookieJar: CookieJar, name: string): bool {.inline.} =
  cookieJar.data.hasKey(name)

proc contains*(cookieJar: CookieJar, name: string): bool {.inline.} =
  cookieJar.data.contains(name)

proc `[]=`*(cookieJar: var CookieJar, name: string, value: string) {.inline.} =
  cookieJar.data[name] = value

proc parse*(cookieJar: var CookieJar, text: string) {.inline.} =
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
  for (name, value) in cookieJar.data.pairs:
    yield (name, value)

iterator keys*(cookieJar: CookieJar): string =
  for name in cookieJar.data.keys:
    yield name

iterator values*(cookieJar: CookieJar): string =
  for value in cookieJar.data.values:
    yield value
