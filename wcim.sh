#!/bin/bash

# Waydroid Custom Image Manager. 
# 
# This will handle some of the basic functions like organizing and swapping out verious images.
# Usage: wcim.sh [options]
# Options:
#   -h | --help | help: Prints this help message.
#   -v | --version | version: Shows version info
#   -a | --add | add (.zip image location): Adds an image to the system
#   -r | --remove | remove (image name): Removes an image from the system
#   -s | --swap | swap (image name): Swaps an image with the current one
#   -l | --list | list: Lists all images in the system
#
# License: GPLv3
# Copyright (C) 2022 Waydroid
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# Author: Jon West 
    
set -e 

version="0.01"
updated="06.11.2022"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
LT_BLUE='\033[0;34m'

NC='\033[0m' # No Color

USER_HOME=$(xdg-user-dir)
SHARED_DIR="$USER_HOME/.local/share/waydroid-image-manager"
IMAGEFOLDER="$SHARED_DIR/images"
TEMPFOLDER="$SHARED_DIR/temp"

addImage() {
    # Import the .zip file containing the images and look for a config in it. 
    # If it exists, then extract it and use it to set the android version.
    # If it doesn't exist, then promt user for the information in the config file.
    android_version=""
    image_name=""
    zip_location=""
    if [ -n "$1" ];then
        zip_location="$1"
    else
        echo "Enter the location of the zip file containing the images."
        read zip_location
    fi
    if [ -n $2 ]; then
        image_name="$2"
    else
        echo "Please enter the name of the image you wish to add."
        read image_name
    fi
    if [ -n $3 ]; then
        android_version="$3"
    else
        echo "Please enter the android version of the image you wish to add."
        read android_version
    fi
    if [ -f $zip_location ]; then
        cleanUpCurrentImage
        echo "Importing image..."
        mkdir -p $TEMPFOLDER
        # unzip -q $zip_location -d $TEMPFOLDER
        7z x $zip_location -o$TEMPFOLDER
        if [ -f $TEMPFOLDER/config.txt ]; then
            echo "Found config.txt in image. Using it to set configs."
            echo "Setting android version to $android_version"
            filename="$1"
            while read -r line; do
                if [[ $line == *"android_version"* ]]; then
                    line="android_version=$android_version"
                    echo $line >> $TEMPFOLDER/config.txt
                elif [[ $line == *"image_name"* ]]; then
                    line="image_name=$image_name"
                    echo $line >> $TEMPFOLDER/config.txt
                fi
            done < $TEMPFOLDER/config.txt
        else
            if [ "$android_version" == "" ]; then
                echo "Android version not set. Please enter the android version of the image you wish to add."
                read android_version
            fi
            echo "android_version=$android_version" > $TEMPFOLDER/config.txt
            if [ "$image_name" == "" ]; then
                echo "Image name not set. Please enter the name of the image you wish to add."
                read image_name
            fi
            echo "image_name=$image_name" >> $TEMPFOLDER/config.txt
        fi
        echo "Adding image..."
        mkdir -p $IMAGEFOLDER/$image_name
        if [ -d $TEMPFOLDER/out/target/product/waydroid_x86_64 ]; then
            echo "Found x86_64 image"
            mv $TEMPFOLDER/out/target/product/waydroid_x86_64/* $TEMPFOLDER
            rm -rf $TEMPFOLDER/out
        elif [ -d $TEMPFOLDER/out/target/product/waydroid_x86 ]; then
            echo "Found x86 image"
            mv $TEMPFOLDER/out/target/product/waydroid_x86/* $TEMPFOLDER
            rm -rf $TEMPFOLDER/out
        elif [ -d $TEMPFOLDER/out/target/product/* ]; then
            echo "Found an unsupported image. Now exiting."
            exit 1
        fi
        if [ -f $TEMPFOLDER/system.img ]; then
            cp -r $TEMPFOLDER/* $IMAGEFOLDER/$image_name
            rm -rf $TEMPFOLDER
            echo "Image added."
            # Prompt user if they would like to set this image as the default.
            echo "Would you like to set this image as the default image? (y/n)"
            read set_default
            if [ $set_default == "y" ]; then
                echo "Setting default image to $image_name"
                setImage $image_name
                echo "running 'waydroid init -f' to update the configs"
                sudo waydroid init -f
                echo "switching Android version to $android_version"
                switchAndroidType $android_version
                sudo systemctl restart waydroid-container.service
            fi
            
        else
            echo "No system.img found in image. Now exiting."
            exit 1
        fi
    else
        echo "Image not found."
    fi  
}

listImages() {
    # List all images in the image folder.
    echo "Listing images..."
    if [ -d $IMAGEFOLDER ]; then
        ls $IMAGEFOLDER
    else
        echo "No images found."
    fi
}

cleanUpCurrentImage() {
    # Cleans up any existing images if found.
    if [ -f /usr/share/waydroid-extra/images/system.img -o -f /usr/share/waydroid-extra/images/vendor.img ]; then
        echo "Making sure Waydroid is not using the images right now..."
        waydroid session stop
        sudo systemctl restart waydroid-container.service
        echo "Cleaning up current image..."
        sudo rm -rf /usr/share/waydroid-extra/images/system.img
        sudo rm -rf /usr/share/waydroid-extra/images/vendor.img
        echo "Current image cleaned up."
        sudo rm -rf /var/lib/waydroid /home/.waydroid ~/waydroid ~/.share/waydroid ~/.local/share/applications/*aydroid* ~/.local/share/waydroid
    else
        echo "No current image found."
    fi
}

setImage() {
    # Set the current image to the one specified.
    # If the image doesn't exist, then prompt the user to add it.
    # If the image does exist, then set the current image to the one specified.
    if [ -d $IMAGEFOLDER/$1 ]; then
        echo "Setting image to $1"
        echo $1 > $SHARED_DIR/current_image.txt
        cleanUpCurrentImage
        echo "Current image set to $1"
        sudo cp -r $IMAGEFOLDER/$1/*.img /usr/share/waydroid-extra/images
        echo "running 'waydroid init -f' to update the configs"
        sudo waydroid init -f
        if [ -f $IMAGEFOLDER/$1/config.txt ]; then
            echo "Reading config.txt for android version"
            while read -r line; do
                if [[ $line == *"android_version"* ]]; then
                    android_version=${line#*=}
                    echo "Setting android version to $android_version"
                    switchAndroidType $android_version
                    echo "Restarting waydroid-container service"
                    sudo systemctl restart waydroid-container.service
                fi
            done < $IMAGEFOLDER/$1/config.txt
        fi
    else
        echo "Image $1 not found."
    fi
}

removeImage() {
    # Remove the image specified.
    # If the image doesn't exist, then prompt the user to add it.
    # If the image does exist, then remove the image.
    if [ $1 == "" ]; then
        echo "Listing available images..."
        listImages
        echo "Which image would you like to remove?"
        read image_name
        if [ -d $IMAGEFOLDER/$image_name ]; then
            echo "Removing image $image_name..."
            rm -rf $IMAGEFOLDER/$image_name
            echo "Image $image_name removed."
        else
            echo "Image $image_name not found."
        fi
    fi
    if [ -f $IMAGEFOLDER/$1 ]; then
        echo "Removing image $1"
        rm -rf $IMAGEFOLDER/$1
        echo "Image $1 removed."
    else
        echo "Image $1 not found."
    fi
}

function switchAndroidType {
    # Switch the android type to the one specified.
    # If the android_version is not passed in, then prompt the user to enter it.
    # If the android_version is passed in, then set the android type to the one specified.

    android_version="$1"
    echo "$1"
    if [ "$1" == "" ]; then
        echo -n "Is this an Android 10 or Android 11 image (10/11)?"
        select ab in "10" "11"; do
            case $ab in
                10 ) echo "Setting system configs for Android 10";
                    sudo -E sed -i 's/aidl3/aidl2/' /etc/gbinder.d/anbox.conf;
                    sudo -E sed -i 's/30/29/' /etc/gbinder.d/anbox.conf;
                    sed -i '/waydroid.active_apps=Waydroid/d' /var/lib/waydroid/waydroid_base.prop;;
                11 ) echo "Setting system configs for Android 11";
                    sudo -E sed -i 's/aidl2/aidl3/' /etc/gbinder.d/anbox.conf;
                    sudo -E sed -i 's/29/30/' /etc/gbinder.d/anbox.conf;
                    echo "waydroid.active_apps=Waydroid" >> /var/lib/waydroid/waydroid_base.prop;;
                * ) echo "invalid";;
            esac
        done 
    else
        if [ "$1" == "10" ]; then
            echo "Setting aidl2 and API 29 for Android 10"
            sudo -E sed -i 's/aidl3/aidl2/' /etc/gbinder.d/anbox.conf;
            sudo -E sed -i 's/30/29/' /etc/gbinder.d/anbox.conf;
            sed -i '/waydroid.active_apps=Waydroid/d' /var/lib/waydroid/waydroid_base.prop;
        elif [ "$1" == "11" ]; then
            echo "Setting aidl3 and API 30 for Android 11"
            sudo -E sed -i 's/aidl2/aidl3/' /etc/gbinder.d/anbox.conf;
            sudo -E sed -i 's/29/30/' /etc/gbinder.d/anbox.conf;
            echo "waydroid.active_apps=Waydroid" >> /var/lib/waydroid/waydroid_base.prop;
        fi
    fi
}

# Sort through flags
while test $# -gt 0 
do
    case $1 in
        # Normal option processing
        -h | --help | help)
            echo "Usage: $0 options"
            echo "options: -h | --help | help: Shows this dialog"
            echo "	  -v | --version | version: Shows version info"
            echo "    -a | --add | add (zip_image_location image_name android_version): Adds an image to the system"
            echo "    -s | --set | set (image_name): Sets the current image to the one specified"
            echo "    -r | --remove | remove (image_name): Removes the image specified"
            echo "    -l | --list: Lists all images"
            exit 0
            ;;
        -v | --version | version)
            echo "Version: Waydroid Image Manager $version"
            echo "Updated: $updated"
            exit 0
            ;;
        -a | --add | add)
            ADD_IMAGE="true";
            ;;
        -s | --set | set)
            SET_IMAGE="true";
            ;;
        -r | --remove | remove)
            REMOVE_IMAGE="true";
            ;;
        -l | --list | list)
            LIST_IMAGES="true";
            ;;
        -t | --type | type)
            SWITCH_TYPE="true";
            ;;
        # ...

        # Special cases
        --)
        break
        ;;
        --*)
        # error unknown (long) option $1
        ;;
        -?)
        # error unknown (short) option $1
        ;;

        # FUN STUFF HERE:
        # Split apart combined short options
        -*)
        split=$1
        shift
        set -- $(echo "$split" | cut -c 2- | sed 's/./-& /g') "$@"
        continue
        ;;

        # Done with options
        *)
        break
        ;;
    esac

    # for testing purposes:
    shift
done

if [ "$ADD_IMAGE" == "true" ]; then
	addImage "$1" "$2" "$3";
elif [ "$SET_IMAGE" == "true" ]; then
    if [ "$1" == "" ]; then
        listImages
        echo "Please input the name from the available images above"
        read image_name
        setImage "$image_name";
    else
        echo "$1"
        setImage "$1";
    fi
elif [ "$REMOVE_IMAGE" == "true" ]; then
    removeImage "$1";
elif [ "$LIST_IMAGES" == "true" ]; then
    listImages;
elif [ "$SWITCH_TYPE" == "true" ]; then
    switchAndroidType "$1";
else
	echo "No options specified, please see -h | --help for more info"
fi

