# Table of Contents
> * [Overview of the script](#overview-of-the-script)
> * [Usage](#usage)



# Overview of the script
I was playing around with making custom Ubuntu Cloud Images so that I could test out Prelude Probes. Enter... Imogen. Working with virt-customize is not a cumbersome task in of itself but I wanted to streamline the process, as well as make it a little more simple for anyone to generate their own images. I also made an effort to validate Prelude credentials to ensure that there are no nasty surprises after the image is deployed. I've also included Salt-minion installation, so that any deployed image is nearly immediately ready for remote orchestration.

This script will likely be improved upon, to include support for other Linux distributions as well as to add support for additional customizations.

If anyone would like any additional features which aren't currently supported, please feel free to open an issue with your request or to create your own fork!


Note about Prelude: 

They're a particularly interesting IT Security company which focuses on adversary emulation. I strongly recommend that any security enthusiast have a look at their repositories, which can be found at https://github.com/preludeorg. 



# Usage
./imogen.sh -d <Install Virtualization Drivers> -p <Install Prelude Probe> -s <Install Salt Minion> -r <Create custom administrator account> -a <Install Additional Packages>

./imogen.sh will check to see if libguestfs-tools is installed. If not, it will install it. Additionally, it will present the user with the option of pulling down the cloudimg of any currently supported Ubuntu LTS branches.

-d will present the user with the option to select either kvm or vmware, installing qemu-guest-agent or open-vm-tools, respectively.

-p installs the prelude probe, and will interactively ask for the prelude-cli account & service token. Once provided, the installation script will execute on first boot and the device will be added to the probe list.

-s asks for the IP address of the salt-master server and then installs python3-pip, along with a salt minion. The user will need to authorize the key on the salt-master server once the image is deployed.

-r will create a custom administrator account for the user to access once the image has been deployed. If selected, it will prompt the user for a username and password to use inside of the image and, additionally, will ask if the user if they would like to deploy an SSH .pub key to this new user profile.

-a will allow the user to add any additional packages available via the default Canonical apt repositories. As far as I'm aware, due to the constraints of virt-customize, it is only possible to install one package at a time.
