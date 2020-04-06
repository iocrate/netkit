import unittest, options, strformat, times
import ../netkit/cookie


suite "SetCookie":
  let
    username = "admin"
    password = "root"

  test "name-value":
    let cookie = initCookie(username, password)
    check:
      cookie.name == username
      cookie.value == password
      cookie.expires.len == 0
      cookie.maxAge.isNone
      cookie.domain.len == 0
      cookie.path.len == 0
      not cookie.secure
      not cookie.httpOnly
      cookie.samesite == Lax
      setCookie(cookie) == fmt"{username}={password}; SameSite=Lax"
      $cookie == setCookie(cookie)

  test "domain":
    let 
      domain = "www.netkit.com"
      cookie = initCookie(username, password, domain = domain)
    check:
      cookie.name == username
      cookie.value == password
      cookie.expires.len == 0
      cookie.maxAge.isNone
      cookie.domain == domain
      cookie.path.len == 0
      not cookie.secure
      not cookie.httpOnly
      cookie.samesite == Lax
      setCookie(cookie) == fmt"{username}={password}; Domain={cookie.domain}; SameSite=Lax"
      $cookie == setCookie(cookie)

  test "path":
    let 
      path = "/index"
      cookie = initCookie(username, password, path = path)
    check:
      cookie.name == username
      cookie.value == password
      cookie.expires.len == 0
      cookie.maxAge.isNone
      cookie.domain.len == 0
      cookie.path == path
      not cookie.secure
      not cookie.httpOnly
      cookie.samesite == Lax
      setCookie(cookie) == fmt"{username}={password}; Path={cookie.path}; SameSite=Lax"
      $cookie == setCookie(cookie)

  test "maxAge":
    let 
      maxAge = 10
      cookie = initCookie(username, password, maxAge = some(maxAge))
    check:
      cookie.name == username
      cookie.value == password
      cookie.expires.len == 0
      cookie.maxAge.isSome
      cookie.domain.len == 0
      cookie.path.len == 0
      not cookie.secure
      not cookie.httpOnly
      cookie.samesite == Lax
      setCookie(cookie) == fmt"{username}={password}; Max-Age={maxAge}; SameSite=Lax"
      $cookie == setCookie(cookie)
  
  test "expires string":
    let 
      expires = "Mon, 6 Apr 2020 12:55:00 GMT"
      cookie = initCookie(username, password, expires)
    check:
      cookie.name == username
      cookie.value == password
      cookie.expires == expires
      cookie.maxAge.isNone
      cookie.domain.len == 0
      cookie.path.len == 0
      not cookie.secure
      not cookie.httpOnly
      cookie.samesite == Lax
      setCookie(cookie) == fmt"{username}={password}; Expires={expires}; SameSite=Lax"
      $cookie == setCookie(cookie)
    
  test "expires DateTime":
    let 
      dt = initDateTime(6, mApr, 2020, 13, 3, 0, 0, utc())
      expires = format(dt, "ddd',' dd MMM yyyy HH:mm:ss 'GMT'")
      cookie = initCookie(username, password, expires)
    check:
      cookie.name == username
      cookie.value == password
      cookie.expires == expires
      cookie.maxAge.isNone
      cookie.domain.len == 0
      cookie.path.len == 0
      not cookie.secure
      not cookie.httpOnly
      cookie.samesite == Lax
      setCookie(cookie) == fmt"{username}={password}; Expires={expires}; SameSite=Lax"
      $cookie == setCookie(cookie)

  test "secure":
    let 
      secure = true
      cookie = initCookie(username, password, secure = secure)
    check:
      cookie.name == username
      cookie.value == password
      cookie.expires.len == 0
      cookie.maxAge.isNone
      cookie.domain.len == 0
      cookie.path.len == 0
      cookie.secure
      not cookie.httpOnly
      cookie.samesite == Lax
      setCookie(cookie) == fmt"{username}={password}; Secure; SameSite=Lax"
      $cookie == setCookie(cookie)

  test "http-only":
    let 
      httpOnly = true
      cookie = initCookie(username, password, httpOnly = httpOnly)
    check:
      cookie.name == username
      cookie.value == password
      cookie.expires.len == 0
      cookie.maxAge.isNone
      cookie.domain.len == 0
      cookie.path.len == 0
      not cookie.secure
      cookie.httpOnly
      cookie.samesite == Lax
      setCookie(cookie) == fmt"{username}={password}; HttpOnly; SameSite=Lax"
      $cookie == setCookie(cookie)

  test "sameSite":
    let 
      sameSite = Strict 
      cookie = initCookie(username, password, sameSite = sameSite)
    check:
      cookie.name == username
      cookie.value == password
      cookie.expires.len == 0
      cookie.maxAge.isNone
      cookie.domain.len == 0
      cookie.path.len == 0
      not cookie.secure
      not cookie.httpOnly
      cookie.samesite == sameSite
      setCookie(cookie) == fmt"{username}={password}; SameSite={sameSite}"
      $cookie == setCookie(cookie)


suite "CookieJar":
  test "parse":
    var cookieJar = initCookieJar()
    cookieJar.parse("username=netkit; password=root")
    check:
      cookieJar["username"] == "netkit"
      cookieJar["password"] == "root"
