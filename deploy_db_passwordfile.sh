#!/bin/bash
#
#####################################################################
#   Name: deploy_db_passwordfile.sh
#
# Author: Michael Messina, Management Consultant TUSC
#
#     Date: 05/07/2014
# Modified: 05/07/2014
#
# Description:
#
# Script to deploy a password file to all other RAC instances
# and corresponding standby instances across primary and standby clusters
#
# Parameters:  password file name to deploy with path included (Example: $ORACLE_HOME/orapwaries1)
#
# Requirements:		None
#
# Limitations:    Not designed or coded to run from crontab
#                 Setup for Availity Exadata Racks Only
#                 Following Availity Exadata Compute Node naming Standards
#
# Example Execution:  ./deploy_db_passwordfile.sh $ORACLE_HOME/dbs/orapwariesq1
#
#####################################################################
#
# Set the environment for the oracle account
. /home/oracle/.bash_profile

# Check if the environment variables were passed
if (( $# < 1 ));then
  echo "Wrong number of arguments, $*, passed to deploy_db_passwordfile.sh, must pass database password file name."
  exit 8
fi

# Set the password file to strip off the instance number
# We will use this for the base name for the entire copy
# to the other environments
export DBPASSFILE=${1%%?}

# Debug display the password file name
#echo ${DBPASSFILE}

# assign a date we can use as part of the logfile
export DTE=`/bin/date +%m%d%C%y%H%M`

# Get the Upper hostname so we can use in in our logfile path
export HOST_LOWER=`hostname | awk '{print tolower($0)}'`

# get the first 8 characters of the hostname to get cluster
# Example: agoprdd2 or dtoprdd1, etc.
export EXARACK_SOURCE=${HOST_LOWER:0:8}

# Debug display the Exadata Source Rack
#echo ${EXARACK_SOURCE}

# get first to characters of host for LOCATION
export EXALOC=${HOST_LOWER:0:2}

# Debug display the exadata 2 character location designation
#echo ${EXALOC}

if [ "${EXALOC}" == "ag" ]
  then
   # set the Exadata Rack Target to Dallas
   export EXARACK_TARGET=${EXARACK_SOURCE:2:6}
   export EXARACK_TARGET="dt${EXARACK_TARGET}"
else
   # set the Exadata Rack Target to Atlanta
   export EXARACK_TARGET=${EXARACK_SOURCE:2:6}
   export EXARACK_TARGET="ag${EXARACK_TARGET}"
fi

# Debug DISPLAY the exadata rack target
#echo ${EXARACK_TARGET}

# Get the host number that we are starting from
HOSTNUMBER=${HOST_LOWER:10:1}

# Debug show the starting Host number so that
# we do not recoy the file to the host we started on
# Source wise
#echo ${HOSTNUMBER}

# Copy the oracle database password file to each of the required locations

#  start with source Rack
# Node 1
if [ "${HOSTNUMBER}" == "1" ]
  then
     echo "Skipping source rack host ${EXARACK_SOURCE}o01-mgmt as it is the source host"
else
   echo "scp ${DBPASSFILE}${HOSTNUMBER} ${EXARACK_SOURCE}o01-mgmt:${DBPASSFILE}1"
   scp ${DBPASSFILE}${HOSTNUMBER} ${EXARACK_SOURCE}o01-mgmt:${DBPASSFILE}1
fi

# Node 2 
if [ "${HOSTNUMBER}" == "2" ]
  then
     echo "Skipping source rack host ${EXARACK_SOURCE}o02-mgmt as it is the source host"
else
   echo "scp ${DBPASSFILE}${HOSTNUMBER} ${EXARACK_SOURCE}o02-mgmt:${DBPASSFILE}2"
   scp ${DBPASSFILE}${HOSTNUMBER} ${EXARACK_SOURCE}o02-mgmt:${DBPASSFILE}2
fi

# Node 3
if [ "${HOSTNUMBER}" == "3" ]
  then
     echo "Skipping source rack host ${EXARACK_SOURCE}o03-mgmt as it is the source host"
else
   echo "scp ${DBPASSFILE}${HOSTNUMBER} ${EXARACK_SOURCE}o03-mgmt:${DBPASSFILE}3"
   scp ${DBPASSFILE}${HOSTNUMBER} ${EXARACK_SOURCE}o03-mgmt:${DBPASSFILE}3
fi

# Node 4
if [ "${HOSTNUMBER}" == "4" ]
  then
     echo "Skipping source rack host ${EXARACK_SOURCE}o04-mgmt as it is the source host"
else
   echo "scp ${DBPASSFILE}${HOSTNUMBER} ${EXARACK_SOURCE}o04-mgmt:${DBPASSFILE}4"
   scp ${DBPASSFILE}${HOSTNUMBER} ${EXARACK_SOURCE}o04-mgmt:${DBPASSFILE}4
fi
   
# Copy to target Rack Nodes
echo "scp ${DBPASSFILE}${HOSTNUMBER} ${EXARACK_TARGET}o01-mgmt:${DBPASSFILE}1"
scp ${DBPASSFILE}${HOSTNUMBER} ${EXARACK_TARGET}o01-mgmt:${DBPASSFILE}1

echo "scp ${DBPASSFILE}${HOSTNUMBER} ${EXARACK_TARGET}o02-mgmt:${DBPASSFILE}2"
scp ${DBPASSFILE}${HOSTNUMBER} ${EXARACK_TARGET}o02-mgmt:${DBPASSFILE}2

echo "scp ${DBPASSFILE}${HOSTNUMBER} ${EXARACK_TARGET}o03-mgmt:${DBPASSFILE}3"
scp ${DBPASSFILE}${HOSTNUMBER} ${EXARACK_TARGET}o03-mgmt:${DBPASSFILE}3

echo "scp ${DBPASSFILE}${HOSTNUMBER} ${EXARACK_TARGET}o04-mgmt:${DBPASSFILE}4"
scp ${DBPASSFILE}${HOSTNUMBER} ${EXARACK_TARGET}o04-mgmt:${DBPASSFILE}4

exit 0
