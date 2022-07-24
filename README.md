<img src="media/icon.svg" width="240">

# Reflect

Real-time network file mirroring utility, aka "self-hosted Dropbox".

## Installation

At this time, **Reflect** can only be compiled from source. Install packages may be made available later, or never.

1. Install the [Dart SDK](https://dart.dev/get-dart) for your platform
2. Get the code as a [zip file](https://github.com/cachapa/reflect/archive/refs/heads/master.zip), or using git: `git clone https://github.com/cachapa/reflect.git`
3. (optional) pre-compile the code to your architecture: `dart compile exe bin/main.dart -o reflect`
4. (optional) copy the executable to your system's bin path, e.g. `sudo mv reflect /usr/local/bin/`

There's an install script in the project root that does most of the above and is verified to Work On My Machine™.

## Usage

**Reflect** can be run either as a client or server and needs at least an instance of each to be useful.

To run as **server**, run reflect with the `share` command and the intended share directory:  
`reflect serve ~/a_shared_folder`

To run as **client**, use the `connect` command followed by your server's address and directory:  
`reflect connect http://localhost:8123 ~/another_shared_folder`

> ⚠️ **Note**: You can run multiple clients and servers on the same system, just exercise your own judgement when pointing them at the same folder.

Run `reflect -h` to see other options.

## Topology

Because **Reflect** server instances are capable of handling multiple simultaneous clients, it is possible to build arbitrarily large networks using common topologies, such as:

**Star**: one node acts as a centralised server and all clients connect to it.

```
  ○   ○
   \ /
○ - ○ - ○
   / \
  ○   ○
```

**Line:** each node daisy-chains to another one.

```
  ○ - ○ - ○ - ○ - ○
```

**Ring:** same as `line` but with the last node looping around to close the circuit.

```
  ○ - ○
 /     \
○       ○
 \     /
  ○ - ○
```

**Rubber Ducky**: a combination of the above.

```
      ○~~○
     (  ○ )-○
○\___ )  ○
 \ ○   ○ )
  \ `○' /
   ○---○
```

## Security

**Reflect** is intended for personal or collaborative use between non-malicious participants.

The following measures aim to prevent access to unauthorized third-parties, so that no data is shared unintentionally:

### Transport Layer

Communication happens exclusively over REST and WebSockets, so securing the transport layer is as simple as hosting your server nodes behind an HTTPS proxy such as [Caddy](https://caddyserver.com) or [NGINX](https://www.nginx.com).

[Click here](CADDY_GUIDE.md) for a Caddy configuration guide.

> ⚠️ **Note**: Modern Android and iOS systems do not like it when apps try to use unsecured sockets. Using an HTTPS proxy is worth the trouble if you think you will want to access your instance from a mobile device.

### Authentication

**Reflect** doesn't have a built-in authentication, instead it relies on an HTTPS proxy (as above). Currently, the client only understands [basic auth](https://en.wikipedia.org/wiki/Basic_access_authentication).

### Permissions

There is no concept of roles or permissions at this time: every node has read and write access to every shared file.

### Filesystem

The file transfer mechanism rejects any paths that aren't descendants of the shared directory.

### (Lack Of) Code Maturity 

Be aware that while a best effort has been made to properly implement these measures, the project is still experimental in nature and is almost guaranteed to contain security holes, or data-eating bugs.

## Conflict Resolution

**Reflect** takes a _laissez-faire_ approach to conflict resolution:

1. The change with the most recent modified date wins (recency bias).
2. Otherwise, the change that is not a deletion wins (avoid data loss).
3. Otherwise, the bigger file size wins (assume added content).
4. Otherwise, the one with the highest md5 wins (deterministic coin-toss).

To ensure clocks are roughly synchronized, the client's system time is verified on connection and rejected if it exceeds the allowed drift (currently 5 mins).

> ⚠️ **Note**: There is no built-in concept of manual conflict resolution or change rollback. Please keep this in mind if your use case doesn't allow for any unintended data loss.

## File Transfer

For the sake of simplicity, the current implementation simply dumps the entire file over a TCP socket without any modern conveniences such as retries, resumes, delta encoding, compression, parallelism, or any other cool tricks.

All files are MD5-hashed to protect against corrupted transfers though. Transfers which fail the MD5 check are simply discarded so the download can be retried.  
Moreover, some effort is made to detect and prevent duplicate transfers, such as when copying or renaming files.

Future versions may improve further on this (perhaps by ~~stealing~~ borrowing from the venerable [rsync](https://rsync.samba.org)).

## Final Words

This is experimental software and while every precaution has been taken to avoid it, there's a chance that a rogue bug may at any time corrupt, destroy, or leak your data.

You really shouldn't use **Reflect** for any files you consider important and/or are not backed up.
