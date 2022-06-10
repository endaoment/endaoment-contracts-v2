# Setting up repository on Windows
This guide contains instructions to set up the repository on Windows machines

## Enable WSL2

To work with the tooling in this repository, you must execute it from a Unix system. WSL2 enables you to use Linux tools completely integrated with Windows without the need of a dual boot.

If you don't have it already on your system, make sure to install it [here](https://docs.microsoft.com/en-us/windows/wsl/install).



## Install Foundry
To install Foundry, open a WSL2 Shell and follow the steps for [Installing Foundry on Linux](https://book.getfoundry.sh/getting-started/installation.html#on-linux-and-macos).

## Install Make
If you don't have `make` installed in your WSL2 instance (can be checked with the `make -version` command), make sure to do so before proceeding. If the version check does not return the version for `make`, install it using the following commands

````shell
sudo apt update
sudo apt install make
````

## Install dependencies
To install the project dependencies, simply run

````shell
make install
````

After that, you should be set to build the project and perform other interactions described in the [README.md](../README.md). Have fun!
