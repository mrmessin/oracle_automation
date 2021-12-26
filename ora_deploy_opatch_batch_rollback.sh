################################################################
#
# Script: ora_deploy_opatch_batch_rollback.sh
#
# Parameters: Filename containing list of patches to apply
#             defaults to ora_deploy_opatch_batch_rollback.txt
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
export ORACLE_SID=$1
export PATCHLIST=$2

# Set location of the script executed this is the location where we will
# look for the patch list file if not supplied
export SCRIPTLOC=`dirname $0`
export SCRIPTDIR=`basename $0`

# Check if ORACLE_SID was passed
if [ -z "${ORACLE_SID}" ]; then
   echo "User did not pass ORACLE_SID setting to default defdb"
   export ORACLE_SID=defdb
fi

# Check if patch list file was passed
if [ -z "${PATCHLIST}" ]; then
   export PATCHLIST=${SCRIPTLOC}/ora_deploy_opatch_batch_rollback.txt
   echo "User did not pass patch list setting patchlist to default ${PATCHLIST}"
fi

# Check if the patchlist file exists
if [ ! -f "${PATCHLIST}" ]; then
   echo "ERROR -> Oracle DB Patching Failed -> ${PATCHLIST} does not exist can not process rollback patching."
   exit 8
fi

# Local hostname
export HOSTNAME=`hostname`

# Set the ORACLE_HOME based on the ORACLE_SID
export ORACLE_HOME=`/usr/local/bin/dbhome ${ORACLE_SID}`

# SHow use what are values are for this patching
echo "HOST is set to -> ${HOSTNAME}"
echo "ORACLE_HOME set to -> ${ORACLE_HOME}"
echo "ORACLE_SID ser to -> ${ORACLE_SID}"
echo "Patch Location set to -> ${PATCHLOCATION}"
echo "Using Patch List -> ${PATCHLIST}"

#
# go through each node in the list in the file and execute patch apply for each patch to HOME
while read -r line
do

# Set patch number from line in file
export PATCHNUMBER=${line}

echo "Rolling back Patch ${PATCHNUMBER}"
$ORACLE_HOME/OPatch/opatch rollback -id ${PATCHNUMBER} -silent

echo "Checking status of Patch ${PATCHNUMBER}"
if $ORACLE_HOME/OPatch/opatch lsinventory | grep ${PATCHNUMBER}; then
  echo "ERROR -> Patch Rollback Not verified for ${PATCHNUMBER}"
  #exit 8
else
  echo "Patch Rollback Verified for ${PATCHNUMBER}"
fi
done < "${PATCHLIST}"

exit 0
