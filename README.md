# powershell setup and runner

This action will install `pwsh` (PowerShell) from the various Microsoft official
installation locations. It is tuned for installing `pwsh` on Linux hosts, but is
likely to work on other operating systems (e.g. OSX). Installation is performed
as follows:

+ When the user in the runner where this action is executing is `root`, and if
  the Linux distribution is one recognised by the underlying
  [`pwsh.sh`][pwsh.sh] script, a package-based, system-wide installation will be
  attempted. If the distribution is now recognised, the second technique will be
  used.
+ When the user in the runner where this action is executing is not `root`, the
  underlying [`pwsh.sh`][pwsh.sh] script will install PowerShell to a persistent
  location, i.e. a directory that depends on the runner, the name of the project
  running the action, but will pertain once a job has ended, so that future
  attempts to run this action on the same runner and project, will not require
  downloading PowerShell again.

## Usage

This action is designed to have good defaults and you shouldn't have to provide
it with specific inputs. For the list of inputs that might be of interest,
consult [action.yml](./action.yml). This action prints out the version of
PowerShell that was installed or already exists upon completion. The action
might actively modify the `PATH` to arrange for making `pwsh` accessible to
further steps in your job.

## Known Limitations

When this action needs to use the "local" installation method, it cannot modify
the underlying operating system so as to turn on globalisation support.
Consequently, this action will actively turn off globalisation support whenever
it has discovered that support cannot be provided. This is achieved by exporting
the environment variable `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT` to all further
steps in the same job as this action is being run. The variable will only be set
in the cases where `pwsh` has reported that it is missing relevant underlying
system libraries.

## Implementation Notes

PowerShell installation is performed by the underlying [`pwsh.sh`][pwsh.sh]
script. The script acts as a wrapper that will first install PowerShell, if
necessary, then run it with all arguments and command-line options that will
follow the `--` separator. In other words, the following command would install
PowerShell, if necessary and then print out the installed version.

```shell
./pwsh.sh -- --version
```
