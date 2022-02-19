/*
	Copyright 2022 Tetralux        <tetraluxonpc@gmail.com>
	Copyright 2022 Colin Davidson  <colrdavidson@gmail.com>
	Copyright 2022 Jeroen van Rijn <nom@duclavier.com>.
	Made available under Odin's BSD-3 license.

	List of contributors:
		Tetralux:        Initial implementation
		Colin Davidson:  Linux platform code, OSX platform code, Odin-native DNS resolver
		Jeroen van Rijn: Cross platform unification, code style, documentation
*/

/*
	Package net implements cross-platform Berkeley Sockets, DNS resolution and associated procedures.
	For other protocols and their features, see subdirectories of this package.
*/
package net

//
// TODO(tetra): Bluetooth, Raw
//

any_socket_to_socket :: proc(any_socket: Any_Socket) -> Socket {
	switch s in any_socket {
	case TCP_Socket:  return Socket(s)
	case UDP_Socket:  return Socket(s)
	case:
		unreachable()
	}
}