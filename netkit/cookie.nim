import options, times


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
