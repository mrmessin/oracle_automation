################################################################
#
# Script: ora_deploy_opatch_batch_apply_local.sh
#
# Parameters: Based location where one off patches are located (ex: /u01/app/oracle/software/Qtr_2018Jan)
#             Filename containing list of patches to apply
#             defaults to ora_deploy_opatch_batch_apply.txt
#
# Process to Apply a list of One off Patches is an ORACLE_HOME
# Using the OPatch Utility
#
# Process assumes defdb entry in /etc/oratab that aligns with
# ORACLE_HOME being patched, other wise ORACLE_SID must be passed
# as first parameter
#
# Process assumes file ora_deploy_opatch_batch_apply.txt is in
# PATCHLOCATION direcory and is a list of one off patches
# to be applied to ORACLE_HOME, can pass file name as 2nd parameter
#
# Process Assumes OPatch Utility is installed in the ORACLE_HOME
################################################################
#
# Patch location
export PATCHLOCATION=$1

# ORACLE_SID for setting home to be patched, optional will default to defdb
export ORACLE_SID=$2

# The file with list of patches to be applied, optional will default to standard file name 
# ora_deploy_opatch_batch_apply.txt in the location with the script process
export PATCHLIST=$3

# Set the location of the script process being run this is where we will look for the 
# Patch list if not supplied
export SCRIPTLOC=`dirname $0`
export SCRIPTDIR=`basename $0`

# Check if ORACLE_SID was passed
if [ -z "${ORACLE_SID}" ]; then
   echo "User did not pass ORACLE_SID setting to default defdb"
   export ORACLE_SID=defdb
fi

# Check if patch list file was passed
if [ -z "${PATCHLIST}" ]; then
   export PATCHLIST=${SCRIPTLOC}/ora_deploy_opatch_batch_apply.txt
   echo "User did not pass patch list setting patchlist to default ${PATCHLIST}"
fi

# Check if the patchlist file exists
if [ ! -f "${PATCHLIST}" ]; then
   echo "ERROR -> Oracle DB Patching Failed -> ${PATCHLIST} does not exist can not process patching."
   exit 8
fi

# Local hostname
export HOSTNAME=`hostname`

# Set the ORACLE_HOME based on the ORACLE_SID
export ORACLE_HOME=`/usr/local/bin/dbhome ${ORACLE_SID}`

# SHow use what are values are for this patching
echo "HOST is set to -> ${HOSTNAME}"
echo "ORACLE_HOME set to -> ${ORACLE_HOME}"
echo "ORACLE_SID set to -> ${ORACLE_SID}"
echo "Patch Location set to -> ${PATCHLOCATION}"
echo "Using Patch List -> ${PATCHLIST}"

#
# go through each node in the list in the file and execute patch apply for each patch to HOME
while read -r line
do

# Set patch number from line in file
export PATCHNUMBER=${line}

echo "Applying Patch ${PATCHNUMBER}"
cd ${PATCHLOCATION}/${PATCHNUMBER}
$ORACLE_HOME/OPatch/opatch apply -silent -ocmrf /u01/app/oracle/software/ocm.rsp

echo "Checking status of Patch ${PATCHNUMBER}"
if $ORACLE_HOME/OPatch/opatch lsinventory | grep ${PATCHNUMBER}; then
  echo "Patch Apply Verified for ${PATCHNUMBER}"
else
  echo "ERROR -> Patch Apply Not verified for ${PATCHNUMBER}"
#  exit 8
fi
done < "${PATCHLIST}"

exit 0
