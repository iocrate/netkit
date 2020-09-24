
type
  IpAddressFamily* {.pure.} = enum ## Describes the type of an IP address.
    IPv6, IPv4                          

  IpAddress* = object
    case family*: IpAddressFamily        ## the type of the IP address (IPv4 or IPv6)
    of IpAddressFamily.IPv6:
      address_v6*: array[0 .. 15, uint8] ## Contains the IP address in bytes in case of IPv6
    of IpAddressFamily.IPv4:
      address_v4*: array[0 .. 3, uint8]  ## Contains the IP address in bytes in case of IPv4
