##############################################################################################
# Script:  ora_deploy_oem_agent_patch.sh
#
# Description:  Oracle Enterprise Manager OEM Agent Patching
#
# Process:  Execute from a central deployment server
#           ssh equiv. that will allow scp and ssh
#           from deploy server to each server where java
#           for agent being updated.
#           Text file containing a list of servers to 
#           update java for the OEM agent.
#
#           Text file can be in format of hostname	agent_home
#           The agent home should be the acutal running agent version location
#
#   		Example:
#						agoquaorm01		/u01/app/oracle/agent/agent_13.2.0.0.0
#						agoquaorm02		/u01/app/oracle/agent12c/agent_13.2.0.0.0
#						agoquaorl11		/u01/app/oracle/product/agent/agent_13.2.0.0.0
#						agoquaorl12		/u01/app/oracle/product/agent/agent_13.2.0.0.0
#
#           Text file containing the patches and their location to be applied
#               Example:
#
#
# Parameters: required:  Text File containing the list of servers and the agent homes
#
# Output:  <Script location on file system>/logs/ora_deploy_oem_agent_patch_<date>.log
#
# Execution:
#	/u01/app/oracle/scripts/ora_deploy_oem_agent_patch.sh /u01/app/oracle/scripts/ora_deploy_oem_agent_prd.txt
#
############################################################################################## 
#
################################################################
# Accept parameter for file with list of nodes to work on
################################################################
export inputfile=$1

################################################################
# Set the file name for the patches
################################################################
export agent_patches=ora_deploy_oem_agent_patch.txt

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
export LOGFILE=ora_deploy_oem_agent_patch_${DTE}.log
export LOG=$LOGPATH/$LOGFILE

#####################################################
# Script Environment variables 
#####################################################
# export the page list (Change as require for process notifications)
export PAGE_LIST=dbas@availity.com,dbas@realmed.com
export EMAIL_LIST=DBAs@availity.com

################################################################
# Check Parameter is valid and file exists
################################################################
if [ ! -f "${inputfile}" ]
then
   echo "Oracle Agent Patch Failed -> ${inputfile} does not exist can not process upgrade."
   echo "Oracle Agent Patch Failed -> ${inputfile} does not exist can not process upgrade." >> ${LOG}
   exit 8
fi

if [ ! -f "${agent_patches}" ]
then
   echo "Oracle Agent Patch Failed -> ${agent_patches} does not exist can not process upgrade."
   echo "Oracle Agent Patch Failed -> ${agent_patches} does not exist can not process upgrade." >> ${LOG}
   exit 8
fi

# For each server we will want to grab the agent home then process the agent update
# Local hostname
export HOSTNAME=`hostname`

echo "Patching Agents for the Following Environments in ${inputfile}"
echo "Patching Agents for the Following Environments in ${inputfile}" >> ${LOG}
cat ${inputfile}
cat ${inputfile} >> ${LOG}

# go through each node in the list in the file and execute upgrade
while read -r line
do
   ########################################################
   # Assign the nodename and agent home for processing
   export nodename=`echo ${line}| awk '{print $1}'`
   export agent_home=`echo ${line}| awk '{print $2}'`

   #########################################################
   # Show execution is processing for node and agent home
   echo "Patching OEM Agent on ${nodename} for Agent Home ${agent_home}"
   echo "Patching OEM Agent on ${nodename} for Agent Home ${agent_home}" >> ${LOG}

   ##############################################
   # Shutdown the OEM Agent on remote node
   echo "Shutting Down Agent on host ${nodename}"
   echo "Shutting Down Agent on host ${nodename}" >> ${LOG}
   export cmd="${agent_home}/bin/emctl stop agent"
   echo ${cmd}
   ssh -n ${nodename} ${cmd} >> ${LOG}
   
   ################################################
   # Check status of the Agent Shutdown
   if [ $? -eq 0 ]; then
       echo "OEM Agent Shutdown for Patching on ${nodename} was successful."
       echo "OEM Agent Shutdown for Patching on ${nodename} was successful." >> ${LOG}
   else
       echo "Patch Failed -> OEM Agent Shutdown for Patching on ${nodename} Failed Due to Error Cancelling process."
       echo "Patch Failed -> OEM Agent Shutdown for Patching on ${nodename} Failed Due to Error Cancelling process." >> ${LOG}
       exit 8
   fi
   
   ###########################################################################
   # Execute opatch for each patch listed in the patch config file 
   while read -r line2
   do
      # Set patch number from line in file
      export PATCH=`echo ${line2}| awk '{print $1}'`
      export apply=`echo ${line2}| awk '{print $2}'`

      echo "----------------------- ${PATCH} -----------------------------------------------------"
      echo "----------------------- ${PATCH} -----------------------------------------------------" >> ${LOG}
      echo "Applying Patch ${PATCH} for ${agent_home} on ${nodename}"
      echo "Applying Patch ${PATCH} for ${agent_home} on ${nodename}" >> ${LOG}
      cmd="export ORACLE_HOME=${agent_home}; cd ${PATCH} ; ${agent_home}/OPatch/opatch ${apply} -silent"
      echo ${cmd}
      echo ${cmd} >> ${LOG}
      ssh -n ${nodename} ${cmd} >> ${LOG}

      # Check status of OPatch
      if [ $? -eq 0 ]; then
         echo "OEM Agent Patch on ${nodename} was successful."
         echo "OEM Agent Patch on ${nodename} was successful." >> ${LOG}
      else
         echo "Patch Failed -> OEM Agent Patch on ${nodename} Failed Due to Error Cancelling process."
         echo "Patch Failed -> OEM Agent Patch on ${nodename} Failed Due to Error Cancelling process." >> ${LOG}
         exit 8
      fi
   done < ${agent_patches}
   
   #######################################################
   # Start the OEM Agent 
   echo "Start OEM Agent on Node ${nodename}"
   echo "Start OEM Agent on Node ${nodename}" >> ${LOG}
   export cmd="export ORACLE_HOME=${agent_home}; ${agent_home}/bin/emctl start agent"
   echo ${cmd}
   ssh -n ${nodename} ${cmd} >> ${LOG}
   
   # Check Start of Agent Post Patch
   if [ $? -eq 0 ]; then
       echo "OEM Agent Start on ${nodename} was successful."
       echo "OEM Agent Start on ${nodename} was successful." >> ${LOG}
   else
       echo "Update Failed -> OEM Agent Start on ${nodename} Failed Due to Error Cancelling process."
       echo "Update Failed -> OEM Agent Start on ${nodename} Failed Due to Error Cancelling process." >> ${LOG}
       exit 8
   fi
   
   echo "OEM Agent Patch on ${nodename} was successful." 
   echo "OEM Agent Patch on ${nodename} was successful."  >> ${LOG}
done < ${inputfile}

echo "-------------------------------------------------------------------------------------"
echo "-------------------------------------------------------------------------------------" >> ${LOG}
echo "All nodes in list ${inpufile} successful."
echo "All nodes in list ${inpufile} successful." >> ${LOG}

exit 0
