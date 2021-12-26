##############################################################################################
# Script:  ora_deploy_oem_agent_java_version_update.sh
#
# Description:  Oracle Enterprise Manager OEM Agent
#               Java Version Update
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
# Parameters: required:  Text File containing the list of servers and the agent homes
#
# Output:  <Script location on file system>/logs/ora_deploy_oem_agent_java_version_update_<date>.log
# Execution:
#	/u01/app/oracle/scripts/ora_oem_java_agent_version_update.sh /u01/app/oracle/scripts/ora_deploy_oem_agent_nonprod.txt
#
############################################################################################## 
#
################################################################
# Accept parameter for file with list of nodes to work on
################################################################
export inputfile=$1

##################################################################################
# Java JDK to use to update the Agents, this must exist locally on deploy server
# This will be the JAVA JDK that will be used to put into the Agent home on each
# Server in the agent location for the server and a sym link created replace
# this location when java version to be used changes
##################################################################################
export JDK_JAVA=/u01/app/oracle/software/Qtr_2018July_OEM132/jdk1.7.0_171/
export JDK_JAVA_DIRECTORY=jdk1.7.0_171

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
export LOGFILE=ora_deploy_oem_agent_java_version_update_${DTE}.log
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
   echo "Oracle Agent JAVA JDK Update Failed -> ${inputfile} does not exist can not process upgrade."
   echo "Oracle Agent JAVA JDK Update Failed -> ${inputfile} does not exist can not process upgrade." >> ${LOG}
   exit 8
fi

# Check if the location of the Java to be deployed exists
if [ -d "${JDK_JAVA}" ]; then
   echo "Location of New JDK ${JDK_JAVA} exists will continue...."
   echo "Location of New JDK ${JDK_JAVA} exists will continue...." >> ${LOG}
else
   echo "Update Failed -> Location of New JDK ${JDK_JAVA} does not exist aborting process."
   echo "Update Failed -> Location of New JDK ${JDK_JAVA} does not exist aborting process." >> ${LOG}
   exit 8
fi

# For each server we will want to grab the agent home then process the agent update
# Local hostname
export HOSTNAME=`hostname`

echo "Updating the JDK for Agents for the Following Environments in ${inputfile}"
echo "Updating the JDK for Agents for the Following Environments in ${inputfile}" >> ${LOG}
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
   echo "Processing OEM Agent Java JDK Update on ${nodename} for Agent Home ${agent_home}"
   echo "Processing OEM Agent Java JDK Update on ${nodename} for Agent Home ${agent_home}" >> ${LOG}

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
      echo "OEM Agent Shutdown for JAVA JDK Update on ${nodename} was successful."
      echo "OEM Agent Shutdown for JAVA JDK Update on ${nodename} was successful." >> ${LOG}
   else
      echo "Update Failed -> OEM Agent Shutdown for JAVA JDK Update on ${nodename} Failed Due to Error Cancelling process."
      echo "Update Failed -> OEM Agent Shutdown for JAVA JDK Update on ${nodename} Failed Due to Error Cancelling process." >> ${LOG}
      exit 8
   fi
   
   ###########################################################################
   # Copy the new JAVA JDK to the new node at the JDK Location for the Agent
   echo "Copy New JAVA JDK to ${nodename} in ${agent_home}/oracle_common"
   echo "Copy New JAVA JDK to ${nodename} in ${agent_home}/oracle_common" >> ${LOG}
   scp -r ${JDK_JAVA} ${nodename}:${agent_home}/oracle_common
   
   # Check status of copy of new Java JDK location to node
   if [ $? -eq 0 ]; then
      echo "OEM Agent JAVA JDK Copy to ${nodename} was successful."
      echo "OEM Agent JAVA JDK Copy to ${nodename} was successful." >> ${LOG}
   else
      echo "Update Failed -> OEM Agent JAVA JDK Copy to ${nodename} Failed Due to Error Cancelling process."
      echo "Update Failed -> OEM Agent JAVA JDK Copy to ${nodename} Failed Due to Error Cancelling process." >> ${LOG}
      exit 8
   fi
   
   ####################################
   # Backup the current JDK
   echo "Taking backup of exisintg JDK for Agent on ${nodename} ${agent_home}/oracle_common/jdk.back.${DTE}"
   echo "Taking backup of exisintg JDK for Agent on ${nodename} ${agent_home}/oracle_common/jdk.back.${DTE}" >> ${LOG}
   export cmd="mv ${agent_home}/oracle_common/jdk ${agent_home}/oracle_common/jdk.back.${DTE}"
   echo ${cmd}
   ssh -n ${nodename} ${cmd} >> ${LOG} </dev/null

   # Check status of backup of old Java JDK location on node
   if [ $? -eq 0 ]; then
      echo "OEM Agent JAVA JDK Backup of JDK location on ${nodename} was successful."
      echo "OEM Agent JAVA JDK Backup of JDK location on ${nodename} was successful." >> ${LOG}
   else
      echo "Update Failed -> OEM Agent JAVA JDK Backup of JDK location on ${nodename} Failed Due to Error Cancelling process."
      echo "Update Failed -> OEM Agent JAVA JDK Backup of JDK location on ${nodename} Failed Due to Error Cancelling process." >> ${LOG}
      exit 8
   fi
   
   ##########################################################
   # Set the Sym link for the jdk in agent home to new JDK
   echo "Creating Symbolic Link jdk to new installed JDK on ${nodename} for ${agent_home}/oracle_common/${JDK_JAVA_DIRECTORY}"
   echo "Creating Symbolic Link jdk to new installed JDK on ${nodename} for ${agent_home}/oracle_common/${JDK_JAVA_DIRECTORY}" >> ${LOG}
   export cmd="ln -fs ${agent_home}/oracle_common/${JDK_JAVA_DIRECTORY} ${agent_home}/oracle_common/jdk"
   echo ${cmd}
   ssh -n ${nodename} ${cmd} >> ${LOG}
 
   # Check status of backup of old Java JDK location on node
   if [ $? -eq 0 ]; then
       echo "OEM Agent JAVA JDK Symbolic Link to new JDK location on ${nodename} was successful."
	   echo "OEM Agent JAVA JDK Symbolic Link to new JDK location on ${nodename} was successful." >> ${LOG}
   else
       echo "Update Failed -> OEM Agent JAVA Symbolic Link to new JDK location on ${nodename} Failed Due to Error Cancelling process."
	   echo "Update Failed -> OEM Agent JAVA Symbolic Link to new JDK location on ${nodename} Failed Due to Error Cancelling process." >> ${LOG}
       exit 8
   fi

   #######################################################
   # Start the OEM Agent on remote node after JDK Update
   echo "Start OEM Agent on Node ${nodename} after JDK Update"
   echo "Start OEM Agent on Node ${nodename} after JDK Update" >> ${LOG}
   export cmd="export ORACLE_HOME=${agent_home}; ${agent_home}/bin/emctl start agent"
   echo ${cmd}
   ssh -n ${nodename} ${cmd} >> ${LOG}
   
   # Check Start of Agent Post Update of JAVA JDK
   if [ $? -eq 0 ]; then
      echo "OEM Agent Start on ${nodename} was successful."
      echo "OEM Agent Start on ${nodename} was successful." >> ${LOG}
   else
      echo "Update Failed -> OEM Agent Start on ${nodename} Failed Due to Error Cancelling process."
      echo "Update Failed -> OEM Agent Start on ${nodename} Failed Due to Error Cancelling process." >> ${LOG}
      exit 8
   fi
   
   echo "OEM Agent JAVA JDK Update on ${nodename} was successful." 
   echo "OEM Agent JAVA JDK Update on ${nodename} was successful."  >> ${LOG}
done < ${inputfile}

echo "All nodes in list ${inpufile} successful."
echo "All nodes in list ${inpufile} successful." >> ${LOG}

exit 0
