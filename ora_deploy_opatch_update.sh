#######################################################################################################
# ora_deploy_opatch_update.sh
#
# Description: Run upgrade of OPatch in ORACLE_HOMEs
#              for a node(s)
#
# Dependancies:  
#                ora_deploy_opatch_nodes_{env}.txt [default: ora_deploy_opatch_nodes.txt] (${inputfile}) can pass as parameter a file with a different node list
#                                       node ORACLE_HOME NewOPatchLocation
#                                       node ORACLE_HOME NewOPatchLocation
# Parameters:    environment set to use for paramter files for example
#                pass value of dev and all file parameters become filename${env}.txt
#                if no value passed then filename is filename.txt
#
# Output:  <Script location on file system>/logs/ora_deploy_opatch_<date>.log
#
# Execution:   From central deploy/monitor node
#                               /u01/app/oracle/scripts/ora_deploy_opatch_update.sh
#                               or
#                               /u01/app/oracle/scripts/ora_deploy_opatch_update.sh <env>
#######################################################################################################
#
####################################################################################
# Accept parameter for file designation for the environment set to use 
# If not provided the process will default to use ora_deploy_opatch_nodes.txt
# if environment provided then it is ora_deploy_opatch_nodes_${envinputfile}.txt
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
export LOGFILE=ora_deploy_opatch_${envinputfile}_${DTE}.log
export LOG=$LOGPATH/$LOGFILE

#####################################################
# Script Environment variables
#####################################################
# export the page list (Change as require for process notifications)
export PAGE_LIST=ms_us@advizex.com
export EMAIL_LIST=ms_us@advizex.com

echo "###########################################################################################"
echo "###########################################################################################" >> ${LOG}
echo "Checking Parameters and files for OPatch Update Process....."
echo "Checking Parameters and files for OPatch Update Process....." >> ${LOG}

################################################################################################
# Configuration Files for datapatch apply for instances this is standard and not configurable
# is is a fixed list of nodes, instance and dbname to do the post datapatch operation
# the other files for pathfile and patupupdate file are also considered fix, but
# setting the environment variables to other file names will allow those files to be used
if [ "${envinputfile}" = "" ]
 then
   echo "No env designation provided defaulting"
   echo "No env designation provided defaulting" >> ${LOG}
   export inputfile=${SCRIPTLOC}/ora_deploy_opatch_nodes.txt
else
   echo "Env designation provided setting filenames with _${envinputfile}" 
   echo "Env designation provided setting filenames with _${envinputfile}" >> ${LOG}
   export inputfile=${SCRIPTLOC}/ora_deploy_opatch_nodes_${envinputfile}.txt
fi

################################################################
# Check Parameter is valid and files exist
################################################################
if [ ! -f "${inputfile}" ]
then
   echo "Node/home list file provided -> ${inputfile} does not exist can not process opatch update."
   echo "Node/home list file provided -> ${inputfile} does not exist can not process opatch update." >> ${LOG}
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
echo "Running OPatch Update for each node/home in ${inputfile}"
echo "Running OPatch Update for each node/home in ${inputfile}" >> ${LOG}
cat ${inputfile}
cat ${inputfile} >> ${LOG}

#################################################################################
# go through each node in the list in the file and execute opatch upgrade/patching
while read -r line
do 
   ###########################################################################
   # Assign the nodename, oracle_home and New Opatch Location for processing
   export nodename=`echo ${line}| awk '{print $1}'`
   export oraclehome=`echo ${line}| awk '{print $2}'`
   export newopatch=`echo ${line}| awk '{print $3}'`
   
   echo "#################################################################################################"
   echo "#################################################################################################" >> ${LOG}
   echo "Processing Oracle HOME for ${nodename} - ${oraclehome}"
   echo "Processing Oracle HOME for ${nodename} - ${oraclehome}" >> ${LOG}

   ###############################################################################################
   # Apply OPatch Update to ORACLE_HOME
   ###############################################################################################
   echo "----------------------------------------------------------------------------------------------"
   echo "----------------------------------------------------------------------------------------------" >> ${LOG}
   echo "Applying OPatch Update on ${nodename} for ORACLE_HOME ${oraclehome} from ${newopatch}"  
   echo "Applying OPatch Update on ${nodename} for ORACLE_HOME ${oraclehome} from ${newopatch}" >> ${LOG}

   # Command to save the existing OPatch in the oracle home
   cmd="export ORACLE_HOME=${oraclehome}; cd ${oraclehome}; mv OPatch OPatch.${DTE}"
   
   # Execute the command on remote node
   ssh -tt -n ${nodename} ${cmd} >> ${LOG}
   
   # Check is issue with last command
   if [ $? -eq 0 ]; then
      echo "Saving Current OPatch for ${nodename} -> ${oraclehome} Successful to ${oraclehome}/OPatch.${DTE}."
      echo "Saving Current OPatch for ${nodename} -> ${oraclehome} Successful to ${oraclehome}/OPatch.${DTE}." >> ${LOG}
   else
      echo "ERROR -> Saving Current OPatch for ${nodename} -> ${oraclehome} Failed to ${oraclehome}/OPatch.${DTE}, aborting...."
      echo "ERROR -> Saving Current OPatch for ${nodename} -> ${oraclehome} Failed to ${oraclehome}/OPatch.${DTE}, aborting...." >> ${LOG}
      exit 8
   fi
   
   # Command to create new OPatch directory in the oracle home
   cmd="export ORACLE_HOME=${oraclehome}; cd ${oraclehome}; mkdir OPatch; chmod 775 OPatch"

   # Execute the command on the remote node
   ssh -tt -n ${nodename} ${cmd} >> ${LOG}
      
   # Check is issue with last command
   if [ $? -eq 0 ]; then
      echo "Creating New OPatch Location ${oraclehome}/OPatch on ${nodename} Successful."
      echo "Creating New OPatch Location ${oraclehome}/OPatch on ${nodename} Successful." >> ${LOG}
   else
      echo "ERROR -> Creating New OPatch Location ${oraclehome}/OPatch on ${nodename} Not Successful, aborting...."
      echo "ERROR -> Creating New OPatch Location ${oraclehome}/OPatch on ${nodename} Not Successful, aborting...." >> ${LOG}
      exit 8
   fi
   
   # Command to Put the new OPatch version in the ORACLE_HOME
   cmd="cp -r ${newopatch}/* ${oraclehome}/OPatch"

   # Execute the command on the remote node
   ssh -tt -n ${nodename} ${cmd} >> ${LOG}

   # May need to put in opatch lsinventory grep for post check as warnings may cause command check to fail.
   # Check is issue with last command
   if [ $? -eq 0 ]; then
      echo "Oracle OPatch ${patchlocation} to ${oraclehome}/OPatch on ${nodename} Successful"
      echo "Oracle OPatch ${patchlocation} to ${oraclehome}/OPatch on ${nodename} Successful" >> ${LOG}
   else
      echo "ERROR -> Oracle OPatch ${newopatch} to ${oraclehome}/OPatch on ${nodename} Failed, aborting...."
      echo "ERROR -> Oracle OPatch ${newopatch} to ${oraclehome}/OPatch on ${nodename} Failed, aborting...." >> ${LOG}
      exit 8
   fi
done < "${SCRIPTLOC}/${inputfile}"

echo "#######################################################################################################################"
echo "#######################################################################################################################" >> ${LOG}
echo "OPatch Update for all ORACLE_HOMEs Complete."
echo "OPatch Update for all ORACLE_HOMEs Complete." >> ${LOG}

exit 0
