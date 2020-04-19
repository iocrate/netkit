discard """
  cmd:      "nim c -r --styleCheck:hint --panics:on $options $file"
  matrix:   "--gc:arc"
  targets:  "c"
  nimout:   ""
  action:   "run"
  exitcode: 0
  timeout:  60.0
"""
import unittest
import options
import strformat
import times
import netkit/http/serializers/cookie

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


suite "Parse":
  test "parse cookie from string":
    let 
      text = "admin=root; Domain=www.netkit.com; Secure; HttpOnly"
      cookie = initCookie(text)
    check:
      cookie.name == "admin"
      cookie.value == "root"
      cookie.domain == "www.netkit.com"
      cookie.secure
      cookie.httpOnly
      cookie.sameSite == None
      setCookie(cookie) == text
      $cookie == setCookie(cookie)

  test "parse samesite":
    let 
      expectedLax =  "foo=bar; SameSite=Lax"
      expectedStrict =  "foo=bar; SameSite=Strict"
      expectedNone = "foo=bar"

    check:
      $initCookie("foo=bar; SameSite=Lax") == expectedLax
      $initCookie("foo=bar; SameSite=LAX") == expectedLax
      $initCookie("foo=bar; SameSite=lax") == expectedLax
      $initCookie("foo=bar; SAMESITE=Lax") == expectedLax
      $initCookie("foo=bar; samesite=Lax") == expectedLax
      
      $initCookie("foo=bar; SameSite=Strict") == expectedStrict
      $initCookie("foo=bar; SameSite=STRICT") == expectedStrict
      $initCookie("foo=bar; SameSite=strict") == expectedStrict
      $initCookie("foo=bar; SAMESITE=Strict") == expectedStrict
      $initCookie("foo=bar; samesite=Strict") == expectedStrict

      $initCookie("foo=bar; SameSite=None") == expectedNone
      $initCookie("foo=bar; SameSite=NONE") == expectedNone
      $initCookie("foo=bar; SameSite=none") == expectedNone
      $initCookie("foo=bar; SAMESITE=None") == expectedNone
      $initCookie("foo=bar; samesite=None") == expectedNone

  test "parse error":
    expect MissingValueError:
      discard initCookie("bar")

    expect MissingValueError:
      discard initCookie("=bar")

    expect MissingValueError:
      discard initCookie(" =bar")

    expect MissingValueError:
      discard initCookie("foo=")

  test "parse pair":
    check $initCookie("foo", "bar=baz") == "foo=bar=baz; SameSite=Lax"

    check:
      initCookie("foo=bar=baz").name == "foo"
      initCookie("foo=bar=baz").value == "bar=baz"

    check:
      $initCookie("foo=bar") == "foo=bar"
      $initCookie(" foo = bar ") == "foo = bar "
      $initCookie(" foo=bar ;Path=") == "foo=bar "
      $initCookie(" foo=bar ; Path= ") == "foo=bar "
      $initCookie(" foo=bar ; Ignored ") == "foo=bar "

    check:
      $initCookie("foo=bar; HttpOnly") != "foo=bar"
      $initCookie("foo=bar;httpOnly") != "foo=bar"

    check:
      $initCookie("foo=bar; secure") == "foo=bar; Secure"
      $initCookie(" foo=bar;Secure") == "foo=bar; Secure"
      $initCookie(" foo=bar;SEcUrE=anything") == "foo=bar; Secure"
      $initCookie(" foo=bar;httponyl;SEcUrE") == "foo=bar; Secure"


suite "CookieJar":
  test "parse":
    var cookieJar = initCookieJar()
    cookieJar.parse("username=netkit; password=root")
    check:
      cookieJar["username"] == "netkit"
      cookieJar["password"] == "root"
