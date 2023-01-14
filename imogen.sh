#!/bin/bash

### This script assists with the customization of Ubuntu LTS Cloud images.
### Written and tested on Ubuntu LTS 22.04.1

if [[ ! $UID -eq 0 ]]; then
    echo "Sudo is required to run imogen"
    exit 1

fi

# Ensure that libguestfs-tools is installed. Install if it is not.
if [[ $(dpkg -l libguestfs-tools) != *"ii  libguestfs-tools"* ]]; then
  apt update -y && apt install libguestfs-tools -y

fi

function usage {
    echo
    echo "Usage: $(basename $0) -d <Install Virtualization Drivers> -p <Install Prelude Probe> -s <Install Salt Minion> -u <Create custom administrator account>" 2>&1
    echo
    echo '  -h                          Shows Usage'
    echo '  -d                          Select Virtualization Drivers (optional)'
    echo '  -p                          Install Prelude Probe (optional)'
    echo "  -s                          Installs Salt Minion (optional)"
    echo "  -r                          Creates a unique administrator account. (optional)"
    echo "  -a                          Installs additional apt packages (optional)"
    echo
    exit
}

# Download Ubuntu LTS cloud images, save into /tmp/.
function getUbuntuVersion {

  echo
  echo "Supported Ubuntu versions:"
  echo
  echo "Bionic Beaver (18.04)" 
  echo "Focal Fossa (20.04)" 
  echo "Jammy Jellyfish (22.04)"
  echo
  read -p "Select an LTS version of Ubuntu: (bionic/focal/jammy) " UBUNTU_VERSION
  echo

  # Require supported LTS release.
  if [[ ! $UBUNTU_VERSION -eq "bionic" || ! $UBUNTU_VERSION -eq "focal" || ! $UBUNTU_VERSION -eq "jammy" ]]; then
    echo "This script requires a valid, supported LTS branch of Ubuntu"
    getUbuntuVersion

  # If image already exists, validate SHA256 against default Canonical image.
  elif [[ -f /tmp/ubuntu_$UBUNTU_VERSION-cloudimg-$(date +"%Y-%m-%d").img ]]; then 
    SHA256_UBUNTU_IMG=$(sha256sum /tmp/ubuntu_$UBUNTU_VERSION-cloudimg-$(date +"%Y-%m-%d").img)
    wget -O /tmp/ubuntu_SHA256_sums https://cloud-images.ubuntu.com/$UBUNTU_VERSION/current/SHA256SUMS
    
    # Download image if SHA256 fails to validate against Canonical.
    if [[  "$(grep -o $SHA256_UBUNTU_IMG /tmp/ubuntu_SHA256_sums | wc -l)" == "0" ]]; then
      wget -O /tmp/ubuntu_$UBUNTU_VERSION-cloudimg-$(date +"%Y-%m-%d").img https://cloud-images.ubuntu.com/$UBUNTU_VERSION/current/$UBUNTU_VERSION-server-cloudimg-amd64.img
    fi
  
  # Download image if it does not exist on storage.
  elif [[ ! -f /tmp/ubuntu_$UBUNTU_VERSION-cloudimg-$(date +"%Y-%m-%d").img ]]; then
    wget -O /tmp/ubuntu_$UBUNTU_VERSION-cloudimg-$(date +"%Y-%m-%d").img https://cloud-images.ubuntu.com/$UBUNTU_VERSION/current/$UBUNTU_VERSION-server-cloudimg-amd64.img

  fi

}

# Install Virtualization Driver packages.
function getVirtualizationDrivers {

  echo
  read -p "Select which virtualization drivers you would like to install: (kvm/vmware) " VIRTUALIZATION_DRIVERS
  echo

  if [[ "$VIRTUALIZATION_DRIVERS" = "vmware" ]]; then
    virt-customize -a /tmp/ubuntu_$UBUNTU_VERSION-cloudimg-$(date +"%Y-%m-%d").img --install open-vm-tools
  
  elif [[ "$VIRTUALIZATION_DRIVERS" = "kvm" ]]; then
    virt-customize -a /tmp/ubuntu_$UBUNTU_VERSION-cloudimg-$(date +"%Y-%m-%d").img --install qemu-guest-agent
  
  else
    echo
    echo "You must select either 'kvm' or 'vmware' for virtualization drivers. To request other packages, please create an issue with the specific package listed"
    getVirtualzationDrivers
  
  fi

}

# Add Prelude Probe auto-installer to image.
# Intended for scalable environments. Requires the deployment of prelude-cli, as well as a 'registrar service' token.
# For more information: 
# https://docs.prelude.org/docs/prelude-cli
# https://docs.prelude.org/docs/individual-probe-deployment
function installPreludeProbe {

  echo "Please input your Prelude credentials: "
  read -p "Prelude account ID: " PRELUDE_ACCOUNT_ID
  read -p "Prelude service account token: " PRELUDE_SERVICE_ACCOUNT_TOKEN
  echo

  # Generates HTTP code for credential validation.
  CHECK_VALID_CREDS=$(curl -f -X POST -H "account:$PRELUDE_ACCOUNT_ID" -H "token:$PRELUDE_SERVICE_ACCOUNT_TOKEN" -H 'Content-Type: application/json' 'https://api.preludesecurity.com/detect/endpoint' -w '%{http_code}\n' -s)

  if [[ -z "$PRELUDE_ACCOUNT_ID" ]]; then
    echo
    echo "A Prelude Account ID is required to use this feature"
 
  elif [[ -z "$PRELUDE_SERVICE_ACCOUNT_TOKEN" ]]; then
    echo
    echo "A Prelude Service Account Token is required to use this feature"
  
  # At this time, 40x errors indicate bad credentials. If one of these errors is identified, require user to input credentials again.
  elif [[ $(echo $CHECK_VALID_CREDS | grep -o  '40' | wc -l ) == "1"  ]]; then
    echo "Prelude Probe requires valid credentials. Please try again. "
    installPreludeProbe
 
  else
    curl -o /tmp/install.sh -L https://raw.githubusercontent.com/preludeorg/libraries/master/shell/probe/install.sh
    
    # Replacement regex strings to import valid Prelude credentials into probe install.sh script.
    sed -i s/PRELUDE_ACCOUNT_ID=\"\"/PRELUDE_ACCOUNT_ID=\"$PRELUDE_ACCOUNT_ID\"/g /tmp/install.sh
    sed -i s/PRELUDE_ACCOUNT_SECRET=\"\"/PRELUDE_ACCOUNT_ID=\"$PRELUDE_SERVICE_ACCOUNT_TOKEN\"/g /tmp/install.sh

    # On first boot, the image will install the probe and establish communication with prelude-cli
    virt-customize -a /tmp/ubuntu_$UBUNTU_VERSION-cloudimg-$(date +"%Y-%m-%d").img --firstboot /tmp/install.sh
  fi
  
}



# Downloads Salt bootstrap to image and adds firstboot command execution to ensure device establishes connection with Salt-master.
function installSaltMinion {

  echo
  read -p "Salt Master IP address: " SALT_MASTER_IP
  echo 

  if [[ -z "$SALT_MASTER_IP" ]]; then
    echo "A Salt-master IP address is required to use this feature"
  
  elif [[ "$SALT_MASTER_IP" ]]; then
    virt-customize -a /tmp/ubuntu_$UBUNTU_VERSION-cloudimg-$(date +"%Y-%m-%d").img --install python3-pip
    virt-customize -a /tmp/ubuntu_$UBUNTU_VERSION-cloudimg-$(date +"%Y-%m-%d").img --run-command "curl -o bootstrap-salt.sh -L https://bootstrap.saltproject.io"
    virt-customize -a /tmp/ubuntu_$UBUNTU_VERSION-cloudimg-$(date +"%Y-%m-%d").img --run-command "chmod +x bootstrap-salt.sh"
    virt-customize -a /tmp/ubuntu_$UBUNTU_VERSION-cloudimg-$(date +"%Y-%m-%d").img --firstboot-command "./bootstrap-salt.sh -P stable -A $SALT_MASTER_IP"
  
  fi
}

# Install any additional packages from default Canonical apt repositories.
# Due to constraints w/ virt-customize, only one package may be installed at a time.
function installAdditionalPackages {

  echo
  echo "Due to constraints with virt-customize, only ONE package may be installed at a time."
  echo
  read -p "Please enter the name of the package you would like to install: " PACKAGE_NAME
  virt-customize -a /tmp/ubuntu_$UBUNTU_VERSION-cloudimg-$(date +"%Y-%m-%d").img --install $PACKAGE_NAME
  read -p "Would you like to install any additional packages from apt? (y/N)" INSTALL_MORE
  echo

  while [[ "$INSTALL_MORE" -eq "y" || "$INSTALL_MORE" = -eq "Y" ]]; do
    read -p "Please enter the name of the package you would like to install: " PACKAGE_NAME
    virt-customize -a /tmp/ubuntu_$UBUNTU_VERSION-cloudimg-$(date +"%Y-%m-%d").img --install $PACKAGE_NAME
    echo
    INSTALL_MORE=n
    read -p "Would you like to install any additional packages from apt? (y/N)" INSTALL_MORE
  
  done

}

function makeAdminUser {

  read -p "Please enter a username for the administrator account: " USERNAME
  echo
  read -p "Please enter a password for the administrator account: " PASSWORD
  echo
  read -p "Would you like to import an SSH key? (y/n)" IMPORT_SSH_STATE
  echo
  
  if [[ $IMPORT_SSH_STATE -eq "y" || $IMPORT_SSH_STATE -eq "Y" ]]; then
    read -p "Please enter the location of the SSH pubkey you would like to import: " SSH_KEY_LOCATION
  
  fi

  if [[ ! -z $USERNAME && ! -z $PASSWORD ]]; then
    virt-customize -a /tmp/ubuntu_$UBUNTU_VERSION-cloudimg-$(date +"%Y-%m-%d").img --run-command "useradd $USERNAME"
    virt-customize -a /tmp/ubuntu_$UBUNTU_VERSION-cloudimg-$(date +"%Y-%m-%d").img --run-command "usermod -aG adm $USERNAME"
    virt-customize -a /tmp/ubuntu_$UBUNTU_VERSION-cloudimg-$(date +"%Y-%m-%d").img --run-command "echo '$USERNAME:$PASSWORD' | chpasswd"
    virt-customize -a /tmp/ubuntu_$UBUNTU_VERSION-cloudimg-$(date +"%Y-%m-%d").img --run-command "mkdir -p /home/$USERNAME/.ssh"
    virt-customize -a /tmp/ubuntu_$UBUNTU_VERSION-cloudimg-$(date +"%Y-%m-%d").img --run-command "chown -R $USERNAME:$USERNAME /home/$USERNAME"
  
  fi

  if [[ -f $SSH_KEY_LOCATION ]]; then
    echo "Importing SSH key"
    virt-customize -a /tmp/ubuntu_$UBUNTU_VERSION-cloudimg-$(date +"%Y-%m-%d").img --ssh-inject $USERNAME:file:$SSH_KEY_LOCATION

  fi

}


getUbuntuVersion

opts="dpsarh"
while getopts ${opts} arg; do
    case ${arg} in
        d)
            getVirtualizationDrivers
            ;;
        p)
            installPreludeProbe
            ;;
        s)
            installSaltMinion
            ;;
        a)
            installAdditionalPackages
            ;;
        r)
            makeAdminUser
            ;;
        h)
            usage
            ;;
        ?)
            echo "Invalid option: -${OPTARG}."
            echo
            usage
            ;;
    esac
done
