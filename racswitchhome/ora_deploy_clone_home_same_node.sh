##########################################################################################################################
# Script: ora_deploy_clone_home_same_node.sh
#
# Last Updated: 09/04/2020
#
# Description: Oracle Clone Home on Same Node
#
# Parameters: control environment list ** Option parameter that specifies the environment
#             
#
# Requirements: Control file ora_deploy_clone_home_same_node_list.txt (ora_deploy_clone_home_same_node_list_${envinputfile}.txt)
#               nodename SOURCE_ORACLE_HOME TARGET_ORACLE_HOME
#               Source ORACLE_HOME must exist
#               /u01/app/oracle/product must exist and have enough space for tar of source ORACLE_HOME
#               ORACLE_BASE assumed to be /u01/app/oracle
#               Assumes all nodes in a cluster exist in node list in the file
#
# Output:  <Script location on file system>/logs/ora_deploy_clone_home_same_node_${envinputfile}_<date>.log
#
# Execution:   From central deploy/monitor node
#                               /u01/app/oracle/scripts/ora_deploy_clone_home_same_node.sh
#                               or
#                               /u01/app/oracle/scripts/ora_deploy_clone_home_same_node.sh <env>
##########################################################################################################################
####################################################################################
# Accept parameter for file designation for the environment set to use 
# If not provided the process will default to use ora_deploy_clone_home_same_node_list.txt
# if environment provided then it is ora_deploy_clone_home_same_node_list_${envinputfile}.txt
####################################################################################
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
export LOGFILE=ora_deploy_clone_home_same_node_${envinputfile}_<date>.log
export LOG=$LOGPATH/$LOGFILE

#####################################################
# Script Environment variables
#####################################################
# export the page list (Change as require for process notifications)
export PAGE_LIST=ms_us@advizex.com
export EMAIL_LIST=ms_us@advizex.com

echo "###########################################################################################"
echo "###########################################################################################" >> ${LOG}
echo "Checking Parameters and files for Patch/Switch home Update Process....."
echo "Checking Parameters and files for Patch/switch home Update Process....." >> ${LOG}

################################################################################################
# Configuration Files for datapatch apply for instances this is standard and not configurable
# is is a fixed list of nodes, instance and dbname to do the post datapatch operation
# the other files for pathfile and patupupdate file are also considered fix, but
# setting the environment variables to other file names will allow those files to be used
if [ "${envinputfile}" = "" ]
 then
   echo "No env designation provided defaulting"
   echo "No env designation provided defaulting" >> ${LOG}
   export inputfile=${SCRIPTLOC}/ora_deploy_clone_home_same_node_list.txt
else
   echo "Env designation provided setting filenames with _${envinputfile}" 
   echo "Env designation provided setting filenames with _${envinputfile}" >> ${LOG}
   export inputfile=${SCRIPTLOC}/ora_deploy_clone_home_same_node_list_${envinputfile}.txt
fi

################################################################
# Check Parameter is valid and files exist
################################################################
if [ ! -f "${inputfile}" ]
then
   echo "Node/home list file provided -> ${inputfile} does not exist can not process clone home update."
   echo "Node/home list file provided -> ${inputfile} does not exist can not process clone home update." >> ${LOG}
   exit 8
fi

echo "#################################################################################################"
echo "Using the Following Parameter Files:"
echo "Using the Following Parameter Files:" >> ${LOG}
echo "${inputfile}"
echo "${inputfile}" >> ${LOG}

# Set Local hostname
export HOSTNAME=`hostname`
echo ${HOSTNAME}
echo ${HOSTNAME} >> ${LOG}

echo "#################################################################################################"
echo "#################################################################################################" >> ${LOG}
echo "Running DB Clone Home for each node/home in ${inputfile}"
echo "Running DB Clone Home for each node/home in ${inputfile}" >> ${LOG}
cat ${inputfile}
cat ${inputfile} >> ${LOG}

# go through each node in the list in the file and execute upgrade/patching
while read -r line
do 
   ########################################################
   # Assign the nodename and home(s) for processing
   export nodename=`echo ${line}| awk '{print $1}'`
   export oldoraclehome=`echo ${line}| awk '{print $2}'`
   export neworaclehome=`echo ${line}| awk '{print $3}'`
   
   echo "#################################################################################################"
   echo "#################################################################################################" >> ${LOG}
   echo "Processing Clone ${oldoraclehome} to ${neworaclehome} for ${nodename}"
   echo "Processing Clone ${oldoraclehome} to ${neworaclehome} for ${nodename}" >> ${LOG}
   
   # Check if the new Home Already Exists
   if ssh ${nodename} '[ -d ${neworaclehome} ]'; then
      echo "New ORACLE_HOME directory exists -> ${neworaclehome} on ${nodename} Can not proceed with Clone, exiting.... "
	  echo "New ORACLE_HOME directory exists -> ${neworaclehome} on ${nodename} Can not proceed with Clone, exiting.... " >> ${LOG}
      exit 8
   fi

   # Check if location we want to use exists
   if ssh ${nodename} '[ -d /u01/app/oracle/product ]'; then
      echo "Path for tar of Source ORACLE_HOME exist on ${nodename} proceeding with Clone"
      echo "Path for tar of Source ORACLE_HOME exist on ${nodename} proceeding with Clone" >> ${LOG}
      exit 8
   else
      echo "Path for tar of Source ORACLE_HOME does not exist on ${nodename} Can not proceed with Clone, exiting.... "
      echo "Path for tar of Source ORACLE_HOME does not exist on ${nodename} Can not proceed with Clone, exiting.... " >> ${LOG}
      exit 8
   fi
   
   #  Tar up the source ORACLE_HOME
   export cmd='tar -cvf /u01/app/oracle/product/backup_source_dbhome.tar ${oldoraclehome}/*'
   ssh -n ${nodename} ${cmd} >> ${LOG}
   
   # Check execution of tar
   if [ $? -eq 0 ]; then
      echo "Tar of ${oldoraclehome} on ${nodename} successful, continuing"
      echo "Tar of ${oldoraclehome} on ${nodename} successful, continuing" >> ${LOG}
   else
      echo "Tar of ${oldoraclehome} on ${nodename} failed, aborting process"
      echo "Tar of ${oldoraclehome} on ${nodename} failed, aborting process" >> ${LOG}
      exit 8
   fi
   
   # Make the new Oracle home directory
   export cmd='mdir ${neworaclehome}'
      ssh -n ${nodename} ${cmd} >> ${LOG}
   
   # Check execution of tar
   if [ $? -eq 0 ]; then
      echo "Create of ${neworaclehome} on ${nodename} successful, continuing"
      echo "Create of ${neworaclehome} on ${nodename} successful, continuing" >> ${LOG}
   else
      echo "Create of ${neworaclehome} on ${nodename} failed, exiting"
      echo "Create of ${neworaclehome} on ${nodename} failed, exiting" >> ${LOG}
      exit 8
   fi
   
   # Untar the source ORACLE_HOME to new location
   export cmd='tar -C ${neworaclehome} -xvf /u01/app/oracle/product/backup_source_dbhome.tar'
   ssh -n ${nodename} ${cmd} >> ${LOG}
   
   # Check execution of tar
   if [ $? -eq 0 ]; then
      echo "Tar of ${oldoraclehome} to ${neworaclehome} on ${nodename} successful, continuing"
      echo "Tar of ${oldoraclehome) to ${neworaclehome} on ${nodename} successful, continuing" >> ${LOG}
   else
      echo "Tar of ${oldoraclehome} to ${neworaclehome} on ${nodename} failed, exiting"
      echo "Tar of ${oldoraclehome) to ${neworaclehome} on ${nodename} failed, exiting" >> ${LOG}
      exit 8
   fi
   
   # Run the command to install new ORACLE_HOME
   export cmd='export ORACLE_HOME=${neworaclehome}; $ORACLE_HOME/perl/bin/perl $ORACLE_HOME/clone/bin/clone.pl "CLUSTER_NODES={dtoprdd3o01-mgmt,dtoprdd3o02-mgmt,dtoprdd3o03-mgmt,dtoprdd3o04-mgmt,dtoprdd3o05-mgmt,dtoprdd3o06-mgmt}" "LOCAL_NODE=dtoprdd3o01-mgmt" ORACLE_BASE="${ORACLE_BASE}" ORACLE_HOME="${neworaclehome}" -defaultHomeName'
   ssh -n ${nodename} ${cmd} >> ${LOG}
   
   # Check execution of tar
   if [ $? -eq 0 ]; then
      echo "Adding new ORACLE_HOME ${neworaclehome} on ${nodename} successful, continuing"
      echo "Adding new ORACLE_HOME ${neworaclehome} on ${nodename} successful, continuing" >> ${LOG}
   else
      echo "Adding new ORACLE_HOME ${neworaclehome} on ${nodename} on ${nodename} failed, exiting"
      echo "Adding new ORACLE_HOME ${neworaclehome} on ${nodename} on ${nodename} failed, exiting" >> ${LOG}
      exit 8
   fi
done < "${inputfile}"
 
echo "#######################################################################################################################"
echo "#######################################################################################################################" >> ${LOG}
echo "ORACLE_HOME Clone Complete."
echo "ORACLE_HOME Clone Complete." >> ${LOG}

exit 0