# IniTool

This command line program reads a named values from a section in an ini
file, and can also write values into a section in an ini file.

**usage**: `initool --get <path-to-ini-file>  <section-name>  <value-name>`

For example, if the ini file was as shown here:

--------------------------------------------------------------------
```
  ; File: sample.ini
  ;
  ; This is just the sample ini file used for testing initool.
  
  [USER]
  username = "John Somebody"
  email = "somebody@domain.com"
  acl = 923784
  
  [CLIENT]
  name = "Acme Trucking"
  this is just some random junk that shouldn't be read by the parser.
  phone = "555-555-1212"
  city = "Boise"
  state = "ID"
  zip = "83713"
```
--------------------------------------------------------------------

## Get

You could read the client's phone number using the `--get` argument:

```
$ initool --get sample.ini  CLIENT  phone
```
Both the section name and the key name comparisons disregard differences in case, so
all of the following would work also:
```
$ initool --get sample.ini  client  phone
$ initool --get sample.ini  client  PHONE
$ initool --get sample.ini  CLIENT  PHONE
```
The phone number would be printed on the terminal

## Use in a Script

To read a value into a shell variable, you could use

```
USERNAME=$(initool --get sample.ini client username)
```

## Set

You can write (insert or update) a value in a .ini file using the `--set` argument:

```
$ initool --set sample.ini user phone 555-111-2222
```


