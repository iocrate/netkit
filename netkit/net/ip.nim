
import std/nativesockets
import std/options

type
  IpAddressFamily* {.pure.} = enum ## Describes the type of an IP address.
    IPv6, IPv4                          

  # IpAddress* = object
  #   case family*: IpAddressFamily        ## the type of the IP address (IPv4 or IPv6)
  #   of IpAddressFamily.IPv6:
  #     address_v6*: array[0 .. 15, uint8] ## Contains the IP address in bytes in case of IPv6
  #   of IpAddressFamily.IPv4:
  #     address_v4*: array[0 .. 3, uint8]  ## Contains the IP address in bytes in case of IPv4

proc toDomain*(family: IpAddressFamily): Domain {.inline.} =
  result = if family == IpAddressFamily.IPv4: Domain.AF_INET else: Domain.AF_INET6

proc toIpAddressFamily*(domain: Domain): IpAddressFamily =
  if domain == Domain.AF_INET:
    result = IpAddressFamily.IPv4
  elif domain == Domain.AF_INET6:
    result = IpAddressFamily.IPv6
  else:
    raise newException(ValueError, "invalid ip address family")


