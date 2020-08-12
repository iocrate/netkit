discard """
  cmd:      "nim c -r --styleCheck:hint --panics:on $options $file"
  matrix:   "--gc:arc"
  targets:  "c"
  nimout:   ""
  action:   "run"
  exitcode: 0
  timeout:  60.0
"""
import options
import strformat
import times
import netkit/http/cookies

# SetCookie
block:
  let
    username = "admin"
    password = "root"

  # name-value
  block:
    let 
      cookie = initCookie(username, password)

    doAssert cookie.name == username
    doAssert cookie.value == password
    doAssert cookie.expires.len == 0
    doAssert cookie.maxAge.isNone
    doAssert cookie.domain.len == 0
    doAssert cookie.path.len == 0
    doAssert not cookie.secure
    doAssert not cookie.httpOnly
    doAssert cookie.samesite == Lax
    doAssert setCookie(cookie) == fmt"{username}={password}; SameSite=Lax"
    doAssert $cookie == setCookie(cookie)

  # domain
  block:
    let 
      domain = "www.netkit.com"
      cookie = initCookie(username, password, domain = domain)

    doAssert cookie.name == username
    doAssert cookie.value == password
    doAssert cookie.expires.len == 0
    doAssert cookie.maxAge.isNone
    doAssert cookie.domain == domain
    doAssert cookie.path.len == 0
    doAssert not cookie.secure
    doAssert not cookie.httpOnly
    doAssert cookie.samesite == Lax
    doAssert setCookie(cookie) == fmt"{username}={password}; Domain={cookie.domain}; SameSite=Lax"
    doAssert $cookie == setCookie(cookie)

  # path
  block:
    let 
      path = "/index"
      cookie = initCookie(username, password, path = path)

    doAssert cookie.name == username
    doAssert cookie.value == password
    doAssert cookie.expires.len == 0
    doAssert cookie.maxAge.isNone
    doAssert cookie.domain.len == 0
    doAssert cookie.path == path
    doAssert not cookie.secure
    doAssert not cookie.httpOnly
    doAssert cookie.samesite == Lax
    doAssert setCookie(cookie) == fmt"{username}={password}; Path={cookie.path}; SameSite=Lax"
    doAssert $cookie == setCookie(cookie)

  # maxAge
  block:
    let 
      maxAge = 10
      cookie = initCookie(username, password, maxAge = some(maxAge))
    
    doAssert cookie.name == username
    doAssert cookie.value == password
    doAssert cookie.expires.len == 0
    doAssert cookie.maxAge.isSome
    doAssert cookie.domain.len == 0
    doAssert cookie.path.len == 0
    doAssert not cookie.secure
    doAssert not cookie.httpOnly
    doAssert cookie.samesite == Lax
    doAssert setCookie(cookie) == fmt"{username}={password}; Max-Age={maxAge}; SameSite=Lax"
    doAssert $cookie == setCookie(cookie)
  
  # expires string
  block:
    let 
      expires = "Mon, 6 Apr 2020 12:55:00 GMT"
      cookie = initCookie(username, password, expires)

    doAssert cookie.name == username
    doAssert cookie.value == password
    doAssert cookie.expires == expires
    doAssert cookie.maxAge.isNone
    doAssert cookie.domain.len == 0
    doAssert cookie.path.len == 0
    doAssert not cookie.secure
    doAssert not cookie.httpOnly
    doAssert cookie.samesite == Lax
    doAssert setCookie(cookie) == fmt"{username}={password}; Expires={expires}; SameSite=Lax"
    doAssert $cookie == setCookie(cookie)
    
  # expires DateTime
  block:
    let 
      dt = initDateTime(6, mApr, 2020, 13, 3, 0, 0, utc())
      expires = format(dt, "ddd',' dd MMM yyyy HH:mm:ss 'GMT'")
      cookie = initCookie(username, password, expires)

    doAssert cookie.name == username
    doAssert cookie.value == password
    doAssert cookie.expires == expires
    doAssert cookie.maxAge.isNone
    doAssert cookie.domain.len == 0
    doAssert cookie.path.len == 0
    doAssert not cookie.secure
    doAssert not cookie.httpOnly
    doAssert cookie.samesite == Lax
    doAssert setCookie(cookie) == fmt"{username}={password}; Expires={expires}; SameSite=Lax"
    doAssert $cookie == setCookie(cookie)

  # secure
  block:
    let
      secure = true
      cookie = initCookie(username, password, secure = secure)

    doAssert cookie.name == username
    doAssert cookie.value == password
    doAssert cookie.expires.len == 0
    doAssert cookie.maxAge.isNone
    doAssert cookie.domain.len == 0
    doAssert cookie.path.len == 0
    doAssert cookie.secure
    doAssert not cookie.httpOnly
    doAssert cookie.samesite == Lax
    doAssert setCookie(cookie) == fmt"{username}={password}; Secure; SameSite=Lax"
    doAssert $cookie == setCookie(cookie)

  # http-only
  block:
    let 
      httpOnly = true
      cookie = initCookie(username, password, httpOnly = httpOnly)

    doAssert cookie.name == username
    doAssert cookie.value == password
    doAssert cookie.expires.len == 0
    doAssert cookie.maxAge.isNone
    doAssert cookie.domain.len == 0
    doAssert cookie.path.len == 0
    doAssert not cookie.secure
    doAssert cookie.httpOnly
    doAssert cookie.samesite == Lax
    doAssert setCookie(cookie) == fmt"{username}={password}; HttpOnly; SameSite=Lax"
    doAssert $cookie == setCookie(cookie)

  # sameSite
  block:
    let 
      sameSite = Strict 
      cookie = initCookie(username, password, sameSite = sameSite)
    
    doAssert cookie.name == username
    doAssert cookie.value == password
    doAssert cookie.expires.len == 0
    doAssert cookie.maxAge.isNone
    doAssert cookie.domain.len == 0
    doAssert cookie.path.len == 0
    doAssert not cookie.secure
    doAssert not cookie.httpOnly
    doAssert cookie.samesite == sameSite
    doAssert setCookie(cookie) == fmt"{username}={password}; SameSite={sameSite}"
    doAssert $cookie == setCookie(cookie)


# Parse
block:
  # parse cookie from string
  block:
    let 
      text = "admin=root; Domain=www.netkit.com; Secure; HttpOnly"
      cookie = initCookie(text)
    
    doAssert cookie.name == "admin"
    doAssert cookie.value == "root"
    doAssert cookie.domain == "www.netkit.com"
    doAssert cookie.secure
    doAssert cookie.httpOnly
    doAssert cookie.sameSite == None
    doAssert setCookie(cookie) == text
    doAssert $cookie == setCookie(cookie)

  # parse samesite
  block:
    let 
      expectedLax =  "foo=bar; SameSite=Lax"
      expectedStrict =  "foo=bar; SameSite=Strict"
      expectedNone = "foo=bar"


    doAssert $initCookie("foo=bar; SameSite=Lax") == expectedLax
    doAssert $initCookie("foo=bar; SameSite=LAX") == expectedLax
    doAssert $initCookie("foo=bar; SameSite=lax") == expectedLax
    doAssert $initCookie("foo=bar; SAMESITE=Lax") == expectedLax
    doAssert $initCookie("foo=bar; samesite=Lax") == expectedLax

    doAssert $initCookie("foo=bar; SameSite=Strict") == expectedStrict
    doAssert $initCookie("foo=bar; SameSite=STRICT") == expectedStrict
    doAssert $initCookie("foo=bar; SameSite=strict") == expectedStrict
    doAssert $initCookie("foo=bar; SAMESITE=Strict") == expectedStrict
    doAssert $initCookie("foo=bar; samesite=Strict") == expectedStrict

    doAssert $initCookie("foo=bar; SameSite=None") == expectedNone
    doAssert $initCookie("foo=bar; SameSite=NONE") == expectedNone
    doAssert $initCookie("foo=bar; SameSite=none") == expectedNone
    doAssert $initCookie("foo=bar; SAMESITE=None") == expectedNone
    doAssert $initCookie("foo=bar; samesite=None") == expectedNone

  # parse error
  block:
    doAssertRaises(MissingValueError):
      discard initCookie("bar")

    doAssertRaises(MissingValueError):
      discard initCookie("=bar")

    doAssertRaises(MissingValueError):
      discard initCookie(" =bar")

    doAssertRaises(MissingValueError):
      discard initCookie("foo=")

  # parse pair
  block:
    doAssert $initCookie("foo", "bar=baz") == "foo=bar=baz; SameSite=Lax"


    doAssert initCookie("foo=bar=baz").name == "foo"
    doAssert initCookie("foo=bar=baz").value == "bar=baz"


    doAssert $initCookie("foo=bar") == "foo=bar"
    doAssert $initCookie(" foo = bar ") == "foo = bar "
    doAssert $initCookie(" foo=bar ;Path=") == "foo=bar "
    doAssert $initCookie(" foo=bar ; Path= ") == "foo=bar "
    doAssert $initCookie(" foo=bar ; Ignored ") == "foo=bar "


    doAssert $initCookie("foo=bar; HttpOnly") != "foo=bar"
    doAssert $initCookie("foo=bar;httpOnly") != "foo=bar"


    doAssert $initCookie("foo=bar; secure") == "foo=bar; Secure"
    doAssert $initCookie(" foo=bar;Secure") == "foo=bar; Secure"
    doAssert $initCookie(" foo=bar;SEcUrE=anything") == "foo=bar; Secure"
    doAssert $initCookie(" foo=bar;httponyl;SEcUrE") == "foo=bar; Secure"


# CookieJar
block:
  # parse
  block:
    var cookieJar = initCookieJar()
    cookieJar.parse("username=netkit; password=root")

    doAssert cookieJar["username"] == "netkit"
    doAssert cookieJar["password"] == "root"
