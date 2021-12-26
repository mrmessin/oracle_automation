#######################################################################################################
# ora_deploy_gi_qtrpatch_update.sh
#
# Description: Run qtr deploy patch process for Grid Infrastructure for a Cluster
#
# Dependencies:  Process Assumes Oracle RAC and Rolling Update
#
#                ora_deploy_gi_qtrpatch.txt
#                    Text file that contains the qtr patch locations for each patch to be applied for database home
#
#                ora_deploy_gi_qtrpatch_nodes.txt
#                                       node ORACLE_HOME
#                                       node ORACLE_HOME
#
# Parameters:    environment for file name for list of node/oraclehome to run patch for
#                if not using parameter defaults to file name listed in dependencies
#                for ora_deploy_gi_qtrpatch.txt
#
# Output:  <Script location on file system>/logs/ora_deploy_gi_qtrpatch_<date>.log
#
# Execution:   From central deploy/monitor node
#                               /u01/app/oracle/scripts/ora_deploy_gi_qtrpatch.sh
#                               or
#                               /u01/app/oracle/scripts/ora_deploy_gi_qtrpatch.sh <environment>
#######################################################################################################
#
###########################################################################################################
# Accept parameter for environment to be part of file with list of nodes to work on
# If not provided the process will default to use ora_deploy_gi_qtrpatch_nodes.txt
# Otherwise will take passed parameter and use filename format ora_deploy_gi_qtrpatch_nodes_<env>.txt
###########################################################################################################
export envinputfile=$1

#####################################################
# Script environment
#####################################################
# assign a date we can use as part of the logfile
export DTE=`/bin/date +%m%d%C%y%H%M`

# Get locations
export SCRIPTLOC=`dirname $0`
export SCRIPTDIR=`basename $0`

# Set the logfile directory
export LOGPATH=${SCRIPTLOC}/logs
export LOGFILE=ora_deploy_gi_qtrpatch_${envinputfile}_${DTE}.log
export LOG=$LOGPATH/$LOGFILE

#####################################################
# Script Environment variables
#####################################################
# export the page list (Change as require for process notifications)
export PAGE_LIST=dbas@availity.com,dbas@realmed.com
export EMAIL_LIST=DBAs@availity.com

echo "###########################################################################################"
echo "###########################################################################################" >> ${LOG}
echo "Checking Parameters for Qtr Patch Update Process....."
echo "Checking Parameters for Qtr Patch Update Process....." >> ${LOG}

################################################################
# Check Parameter was passed if not default to default filename
################################################################
if [ "${envinputfile}" = "" ]
 then
   echo "No env designation provided defaulting"
   echo "No env designation provided defaulting" >> ${LOG}
   export inputfile=${SCRIPTLOC}/ora_deploy_gi_qtrpatch_nodes.txt
   export patchfile=${SCRIPTLOC}/ora_deploy_gi_qtrpatch.txt
else
   echo "Env designation provided setting filenames with _${envinputfile}"
   echo "Env designation provided setting filenames with _${envinputfile}" >> ${LOG}
   export inputfile=${SCRIPTLOC}/ora_deploy_gi_qtrpatch_nodes_${envinputfile}.txt
   export patchfile=${SCRIPTLOC}/ora_deploy_gi_qtrpatch_${envinputfile}.txt
fi

################################################################
# Check if the qtr patch file exists that lists the GI patch updates
################################################################
if [ -z "${patchfile}" ]
then
   echo "No Patch List File Provided ${patchfile} can not proceed with patching"
   echo "No Patch List File Provided ${patchfile} can not proceed with patching" >> ${LOG}
   exit 8
fi   

################################################################
# Check Parameter is valid and file exists
################################################################
if [ ! -f "${inputfile}" ]
then
   echo "Node/home list file provided -> ${inputfile} does not exist can not process qtr patch update."
   echo "Node/home list file provided -> ${inputfile} does not exist can not process qtr patch update." >> ${LOG}
   exit 8
fi

# Set Local hostname
export HOSTNAME=`hostname`
echo ${HOSTNAME}
echo ${HOSTNAME} >> ${LOG}

echo "#################################################################################################"
echo "#################################################################################################" >> ${LOG}
echo "Running Qtr GI Patching for each node/home in ${inputfile}"
echo "Running Qtr GI Patching for each node/home in ${inputfile}" >> ${LOG}
cat ${inputfile}
cat ${inputfile} >> ${LOG}
echo "-"

# We are Just starting at first node (can set for non-prod to N so only 60 second pause)
export first_node="Y"

# go through each node in the list in the file and execute upgrade
while read -r line
do
   ########################################################
   # Assign the nodename and agent home for processing
   export nodename=`echo ${line}| awk '{print $1}'`
   export oraclehome=`echo ${line}| awk '{print $2}'`

   echo "#################################################################################################"
   echo "#################################################################################################" >> ${LOG}
   echo "Processing Oracle HOME for ${nodename} - ${oraclehome}"
   echo "Processing Oracle HOME for ${nodename} - ${oraclehome}" >> ${LOG}

   ###############################################################################################
   # Apply Patch to Database Home
   ###############################################################################################
   echo "----------------------------------------------------------------------------------------------"
   echo "----------------------------------------------------------------------------------------------" >> ${LOG}
   echo "Applying Qtr Database Home Patch on ${nodename} for ORACLE_HOME ${oraclehome}"  
   echo "Applying Qtr Database Home Patch on ${nodename} for ORACLE_HOME ${oraclehome}" >> ${LOG}

   echo "Applying Patches to ${oraclehome}"
   cat ${patchfile}
   cat ${patchfile} >> ${LOG}

   # Execute Process to Apply patches from the ora_deploy_gi_qtrpatch.txt file which lists patch directory patchexec user
   while read -r line2
   do 
      export patchlocation=`echo ${line2}| awk '{print $1}'`
      export patchutil=`echo ${line2}| awk '{print $2}'`
      export execowner=`echo ${line2}| awk '{print $3}'`

      echo "----------------------------------------------------------------------------------------------"
      echo "----------------------------------------------------------------------------------------------" >> ${LOG}
      echo "Executing Patch ${patchlocation} for ${oraclehome} on ${nodename} using ${patchutil} as ${execowner}"
      echo "Executing Patch ${patchlocation} for ${oraclehome} on ${nodename} using ${patchutil} as ${execowner}" >> ${LOG}

      ###########################################################################################################################
      # FUTURE CHECK FOR PATH ALREADY APPLIED THERE ARE MULTIPLE PATCHES HOW DO DO THIS CHECK MAYBE ANOTHER CONFIG THAT LISTS
      # check of the patch is already applied on the remote node if it is we can skip it
      #echo "Checking if Patch ${patchlocation} for ${oraclehome} on ${nodename} is already applied."
      #echo "Checking if Patch ${patchlocation} for ${oraclehome} on ${nodename} is already applied." >> ${LOG}
      #cmd="export ORACLE_HOME=${oraclehome}; cd ${patchlocation}; ${oraclehome}/OPatch/opatch lsinventory | grep patch"
      #echo ${cmd}
   
      # Execute the patch apply on the remote node
      #export results=`ssh -n ${nodename} ${cmd} `
      #echo ${results}
      #echo ${results| >> ${LOG}
      ###########################################################################################################################
      
      # Determine if a root or non-root patch execution    
      if [ "${execowner}" != "root" ]
       then
         cmd="export ORACLE_HOME=${oraclehome}; cd ${patchlocation}; ${oraclehome}/OPatch/${opatchutil} apply"
      else
         cmd="sudo su -c 'export ORACLE_HOME=${oraclehome}; ${oraclehome}/OPatch/${patchutil} apply ${patchlocation} -oh ${oraclehome}'"
      fi
   
      # Show the patch command being executed will help for troubleshooting any issues.      
      echo "Executing Patch Command:"
      echo "Executing Patch Command:" >> ${LOG}
      echo ${cmd}
      echo ${cmd} >> ${LOG}

      # Execute the patch apply on the remote node
      ssh -n -tt ${nodename} ${cmd} >> ${LOG}

      ###########################################################################################################################
      # FUTURE MAY WANT TO CHANGE POST CHECK TO MATCH PRECHECK TO MAKE SURE PATHES ARE APPLIED 
      # AS WARNINGS WOULD CAUSE ABORT OF PATCHING PROCESS AND THIS MAY NOT BE WHAT WE WANT
      ###########################################################################################################################

      # Check is issue with last command
      if [ $? -eq 0 ]; then
         echo "Oracle database patch ${patchlocation} on ${nodename} Successful"
         echo "Oracle database patch ${patchlocation} on ${nodename} Successful" >> ${LOG}
      else
         echo "Oracle database patch ${patchlocation} on ${nodename} Failed, aborting...."
         echo "Oracle database patch ${patchlocation} on ${nodename} Failed, aborting...." >> ${LOG}
         exit 8
      fi
   done < "${patchfile}"

   echo "----------------------------------------------------------------------------------------------"
   echo "----------------------------------------------------------------------------------------------" >> ${LOG}
   echo "ORACLE_HOME Patching for node ${nodename} for ORACLE_HOME ${oraclehome} Complete."
   echo "ORACLE_HOME Patching for node ${nodename} for ORACLE_HOME ${oraclehome} Complete." >> ${LOG}
   echo "--" >> ${LOG}
   echo "--" >> ${LOG}
   echo "--"
   echo "--"
   echo "----------------------------------------------------------------------------------------------"
   echo "----------------------------------------------------------------------------------------------" >> ${LOG}
   echo "Pausing for Period of time before moving to next node for services settlement and Relocate"
   echo "Pausing for Period of time before moving to next node for services settlement and Relocate" >> ${LOG}

   ###############################################################################################
   # If we want to shift services we could develop automated process to move services here
   # Otherwise services will shift when next instance is shutdown as part of RAC
   ###############################################################################################

   # Since we execute in cluster sets we can assume second node is last node and not long wait needed
   if [ "${first_node}" = "Y" ]; then
      export first_node="N"

      # 20 min set is standard for service relocation 10 min and 10min to execute
      sleep 1200
   else
      # Specified to sleep and wait for number of seconds as standard for service relocation
      # For most clusters only 2 nodes so this may not be really needed to be long but
      # enough time to execute service relocation
      sleep 600
   fi

done < "${inputfile}"

echo "#######################################################################################################################"
echo "#######################################################################################################################" >> ${LOG}
echo "Qtr GI Patch Update Process Complete!"
echo "Qtr GI Patch Update Process Complete!" >> ${LOG}

exit 0
