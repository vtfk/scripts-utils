# Citrix Logoff
A simple script to query all servers in an array for users, then kick a specified user based on the UID.

## Usage

Either launch the .exe or the .ps1 file, then input the username when requested.

Or use the terminal and launch it with username as an argument.

```shell
$ citrixlogoff.ps1 <username>
```
```shell
$ citrixlogoff.exe <username>
```

## Building
I´ll keep the binary updated manually until I create a better compiler.

## TODO
- [x] Single session logout (confirm kick)
- [x] Multi session logout (kick from several or all sessions)
- [x] Only one confirmation of kick with as much info as possible
- [ ] Get Citrix servers dynamically
- [ ] Asynchronous server search
- [ ] Build instruction and build script
- [ ] User info from AD (append username with #)

## Contact
Ingar Helgesen - <ingar.helgesen@t-fk.no>

<https://github.com/sherex>