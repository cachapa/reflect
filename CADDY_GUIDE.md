# Caddy guide

[Caddy](https://caddyserver.com) is an HTTP proxy (similar to NGINX) that features automatic handling of HTTPS certificates off the shelf.

This page serves as a guide to set up *reflect* behind an internet-accessible HTTPS endpoint.

## Run reflect server

Make sure you [follow the instructions](README.md) to install *reflect* in your machine;

Run reflect as a server under an arbitrary port and point it to the target directory:

`reflect /path/to/shared/directory -s -p 8123`

## Configure Caddy

Set up Caddy in your platform, and once that's running, edit your Caddyfile (located in `/etc/caddy/Caddyfile` on most Linux distributions):

The following example forwards HTTP connections from a subdomain to reflect:

```
reflect.my-domain.com {
  reverse_proxy localhost:8123
}
```

To add [basic auth](https://en.wikipedia.org/wiki/Basic_access_authentication) with a simple username/password combo:

1. For this example we will go with `username` and `password`
2. Hash the password using `caddy hash-password`
3. Copy the hashed password into your configuration:
```
reflect.my-domain.com {
  reverse_proxy localhost:8123
  basicauth {
    username JDJhJDE0JEhFNEFsd2NWYzNQdkhMTDZGcVFSei5Vdy4vRlc3SVRTZThmb1BzdFZoMW9ZM2hhaVRLYzR1
  }
}
```
4. Reload caddy and try it out: `caddy reload /etc/caddy/Caddyfile`

For troubleshooting or more complex setups you can consult the [official docs](https://caddyserver.com/docs/caddyfile/directives/basicauth).
