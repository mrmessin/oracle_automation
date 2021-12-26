#######################################################################################################
# ora_deploy_db_patch_update_nonrac_switchhome.sh
#
# Description: Run qtr deploy patch process for each database in data list
#              for a node switching database home from curent home to a patched home
#              and running the datapatch
#
# Dependancies:  Process Assumes Oracle non-RAC
#
#                ora_deploy_db_datapatch_non-rolling.sh <paramters will be created as part of process>
#                    Script must be located in the same directory with this script ora_deploy_db_patch_update_nonrac.sh
#
#                ora_deploy_db_patch_nodes_switchhome_{env}.txt (${inputfile}) can pass as parameter a file with a different node list
#                                       node dbinstance OLD_ORACLE_HOME NEW_ORACLE_HOME
#                                       node dbinstance OLD_ORACLE_HOME NEW_ORACLE_HOME
#
#                ora_deploy_pre_patch_exec_{env}.txt     ** optional if files do not exist process will ignore
# 					  list of scripts with full path to execute prior to patching
#
#                ora_deploy_post_patch_exec_{env}.txt    ** optional if files do not exist process will ignore
# 					  list of scripts with full path to execute after patching
#        
#               All Instances for node must exist in the /etc/oratab for process to get ORACLE_HOME
#               The cluster dbname is the database name as identified in clusterware for RAC, if not present then assumes non-RAC
#               The Cluster dbname is important as it tends to be different between primary and standby clusters for database
#               as name in cluster tends to be same as DB unique name.
#
# Parameters:    environment set to use for paramter files for example
#                pass value of dev and all file parameters become filename_${env}.txt
#                if no value passed then filename is filename.txt
#
# Output:  <Script location on file system>/logs/ora_deploy_db_patch_switchhome_<date>.log
#
# Execution:   From central deploy/monitor node
#                               /u01/app/oracle/scripts/ora_deploy_db_patch_switchome.sh
#                               or
#                               /u01/app/oracle/scripts/ora_deploy_db_patch_switchhome.sh <env>
#######################################################################################################
#
####################################################################################
# Accept parameter for file designation for the environment set to use 
# If not provided the process will default to use ora_deploy_db_patch_nodes_switchhome.txt
# if environment provided then it is ora_deploy_db_patch_nodes_switchhome_${envinputfile}.txt
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
export LOGFILE=ora_deploy_db_patch_switchhome_${envinputfile}_${DTE}.log
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
   export inputfile=${SCRIPTLOC}/ora_deploy_db_patch_nodes_switchhome.txt
   export dbpatchupdatepreexec=ora_deploy_pre_patch_exec.txt
   export dbpatchupdatepostexec=ora_deploy_post_patch_exec.txt
else
   echo "Env designation provided setting filenames with _${envinputfile}" 
   echo "Env designation provided setting filenames with _${envinputfile}" >> ${LOG}
   export inputfile=${SCRIPTLOC}/ora_deploy_db_patch_nodes_switchhome_${envinputfile}.txt
   export dbpatchupdatepreexec=ora_deploy_pre_patch_exec_${envinputfile}.txt
   export dbpatchupdatepostexec=ora_deploy_post_patch_exec_${envinputfile}.txt
fi

################################################################
# Check Parameter is valid and files exist
################################################################
if [ ! -f "${inputfile}" ]
then
   echo "Node/home list file provided -> ${inputfile} does not exist can not process patch/switch home update."
   echo "Node/home list file provided -> ${inputfile} does not exist can not process patch/switch home update." >> ${LOG}
   exit 8
fi

echo "#################################################################################################"
echo "Using the Following Parameter Files:"
echo "Using the Following Parameter Files:" >> ${LOG}
echo "${inputfile}"
echo "${inputfile}" >> ${LOG}
echo "${dbpatchupdatepreexec}"
echo "${dbpatchupdatepreexec}" >> ${LOG}
echo "${dbpatchupdatepostexec}"
echo "${dbpatchupdatepostexec}" >> ${LOG}

# Set Local hostname
export HOSTNAME=`hostname`
echo ${HOSTNAME}
echo ${HOSTNAME} >> ${LOG}

echo "#################################################################################################"
echo "#################################################################################################" >> ${LOG}
echo "Running DB Patch/Switch Home for each node/home in ${inputfile}"
echo "Running Qtr DB Patch/Switch Home for each node/home in ${inputfile}" >> ${LOG}
cat ${inputfile}
cat ${inputfile} >> ${LOG}

#################################################################
# Run any scripts put in the pre patch execution file
if [ -f "${SCRIPTLOC}/${dbpatchupdatepreexec}" ] 
 then
echo "Running Pre Patch Processes as defined in ${dbpatchupdatepostexec}"
echo "Running Pre Patch Processes as defined in ${dbpatchupdatepostexec}" >> ${LOG}
while read -r line_script
do
    ssh -n ${nodename} ${line_script}
done < "${SCRIPTLOC}/${dbpatchupdatepreexec}"
fi

# go through each node in the list in the file and execute upgrade/patching
while read -r line
do 
   ########################################################
   # Assign the nodename and home(s) for processing
   export nodename=`echo ${line}| awk '{print $1}'`
   export db=`echo ${line}| awk '{print $2}'`
   export oldoraclehome=`echo ${line}| awk '{print $3}'`
   export neworaclehome=`echo ${line}| awk '{print $4}'`

   echo "#################################################################################################"
   echo "#################################################################################################" >> ${LOG}
   echo "Processing Database ${db} from ${oldoraclehome} to ${neworaclehome} for ${nodename}"
   echo "Processing Database ${db} from ${oldoraclehome} to ${neworaclehome} for ${nodename}" >> ${LOG}
   
   ###############################################################################################
   # Check if database is running in Old ORACLE_HOME we are patching   
   ###############################################################################################
   echo "--------------------------------------------------------------------------------------------------------"
   echo "--------------------------------------------------------------------------------------------------------" >> ${LOG}
   
   # check database instance running on node being patched/switch home
   echo "Checking if Status for ${db} on ${nodename} in ${oldoraclehome}"
   echo "Checking if Status for ${db} on ${nodename} in ${oldoraclehome}" >> ${LOG}

   # Check ORACLE_HOME for instance is our oracle home that we are patching
   cmd="echo `/usr/local/bin/dbhome ${db}` | grep ${oldoraclehome}"
   export result=`ssh -n ${nodename} ${cmd}`

   # Check is issue with last command
   if [ $? -eq 0 ]; then
      echo ""
   else
      echo "Check for running instance for ${db} on ${nodename} in ${oldoraclehome} Failed, aborting......"
      echo "Check for running instance for ${db} on ${nodename} in ${oldoraclehome} Failed, aborting......" >> ${LOG}
      exit 8
   fi
  
   ###############################################################################################
   # Check if standby database
   ###############################################################################################
   echo "Checking if ${db} is a Standby Database"
   echo "Checking if ${db} is a Standby Database" >> ${LOG}
   export cmd="export ORACLE_HOME=${oldoraclehome}; export ORACLE_SID=${db}; echo -e 'set pagesize 0 \nselect database_role from v\$database;' | ${oldoraclehome}/bin/sqlplus -s '/ as sysdba'"
   echo "Executing...... ${cmd}"
   echo "Executing...... ${cmd}" >> ${LOG}
   export dbmode=$(ssh -n ${nodename} ${cmd})
  
   echo "Database Mode is -> ${dbmode}" 
   echo "Database Mode is -> ${dbmode}" >> ${LOG}
   
   ###############################################################################################
   # Switch ORACLE_HOME, update /etc/oratab
   ###############################################################################################
   # create a temp /etc/oratab file on remote node
   echo "Updating /etc/oratab for ${db} from ${oldoraclehome} to ${neworaclehome}" 
   echo "Updating /etc/oratab for ${db} from ${oldoraclehome} to ${neworaclehome}" >> ${LOG}
   srch="${db}:${oldoraclehome}"
   repl="${db}:${neworaclehome}"
   cmd="sed 's|${srch}|${repl}|g' /etc/oratab > ${HOME}/oratab.new"
   echo "Executing...... ${cmd}"
   echo "Executing...... ${cmd}" >> ${LOG}
   ssh -n ${nodename} ${cmd} >> ${LOG}

   # Check is issue with last command
   if [ $? -eq 0 ]; then
      echo ""
   else
      echo "/etc/oratab temp new for ${db} on ${nodename} for ${oldoraclehome} to ${neworaclehome} Failed......"
      echo "/etc/oratab temp new for ${db} on ${nodename} for ${oldoraclehome} to ${neworaclehome} Failed......" >> ${LOG}
      exit 8
   fi

   # take backup of existing /etc/oratab
   cmd="cp /etc/oratab $HOME/oratab.save"
   echo "Executing...... ${cmd}"
   echo "Executing...... ${cmd}" >> ${LOG}
   ssh -n ${nodename} ${cmd} >> ${LOG}

   # Check is issue with last command
   if [ $? -eq 0 ]; then
      echo ""
   else
      echo "/etc/oratab Backup for ${db} on ${nodename} for ${oldoraclehome} to ${neworaclehome} Failed......"
      echo "/etc/oratab Backup for ${db} on ${nodename} for ${oldoraclehome} to ${neworaclehome} Failed......" >> ${LOG}
      exit 8
   fi

   # Put the new oratab.new in place of /etc/oratab
   cmd="cp ${HOME}/oratab.new /etc/oratab"
   echo "Executing...... ${cmd}"
   echo "Executing...... ${cmd}" >> ${LOG}
   ssh -n ${nodename} ${cmd} >> ${LOG}

   # Check is issue with last command
   if [ $? -eq 0 ]; then
      echo ""
   else
      echo "/etc/oratab Replace for ${db} on ${nodename} for ${oldoraclehome} to ${neworaclehome} Failed......"
      echo "/etc/oratab Replace for ${db} on ${nodename} for ${oldoraclehome} to ${neworaclehome} Failed......" >> ${LOG}
      exit 8
   fi

   # Remove the /etc/oratab   
   cmd="rm -f ${HOME}/oratab.new"
   echo "Executing...... ${cmd}"
   echo "Executing...... ${cmd}" >> ${LOG}
   ssh -n ${nodename} ${cmd} >> ${LOG}

   # Check is issue with last command
   if [ $? -eq 0 ]; then
      echo ""
   else
      echo "Removed of temp new /etc/oratab for ${db} on ${nodename} for ${oldoraclehome} to ${neworaclehome} Failed......"
      echo "Removed of temp new /etc/oratab for ${db} on ${nodename} for ${oldoraclehome} to ${neworaclehome} Failed......" >> ${LOG}
      exit 8
   fi

   ###############################################################################################
   # Shutdown instance 
   ###############################################################################################
   echo "Shutting Down ${db} in ${oldoraclehome}" 
   echo "Shutting Down ${db} in ${oldoraclehome}" >> ${LOG}
   export cmd="export ORACLE_HOME=${oldoraclehome}; export ORACLE_SID=${db}; echo -e 'shutdown immediate;' | ${oldoraclehome}/bin/sqlplus '/ as sysdba'"
   echo "Executing...... ${cmd}"
   echo "Executing...... ${cmd}" >> ${LOG}
   ssh -n ${nodename} ${cmd} >> ${LOG}

   # Check is issue with last command
   if [ $? -eq 0 ]; then
      echo "Oracle database ${db} on ${nodename} Shutdown"
      echo "Oracle database ${db} on ${nodename} Shutdown" >> ${LOG}
   else
      echo "Oracle database ${db} on ${nodename} Shutdown Failed, aborting....."
      echo "Oracle database ${db} on ${nodename} Shutdown Failed, aborting....." >> ${LOG}
      exit 8
   fi
		 
   ###############################################################################################
   # Copy files from dbs location for database from old home to new home
   ###############################################################################################
   echo "Copy all files from ${oldoraclehome}/dbs to ${neworaclehome}/dbs for ${db} on ${nodename}"
   echo "Copy all files from ${oldoraclehome}/dbs to ${neworaclehome}/dbs for ${db} on ${nodename}" >> ${LOG}
   cmd="cp ${oldoraclehome}/dbs/*${db}* ${neworaclehome}/dbs"
   echo "Executing...... ${cmd}"
   echo "Executing...... ${cmd}" >> ${LOG}
   ssh -n ${nodename} ${cmd} >> ${LOG}

   ###############################################################################################
   # If Primary database run datapatch
   ###############################################################################################
   if [ "${dbmode}" = "PRIMARY" ]; then
      #################################################################################################
      # Startup database instances on Node for ORACLE_HOME being patched in upgrade mode for datapatch
      # Assumes /etc/oratab is up to date and has instance names in there
      #################################################################################################
      echo "Starting instance ${db} on ${nodename} in New ORACLE_HOME Upgrade Mode -> ${neworaclehome}."
      echo "Starting instance ${db} on ${nodename} in New ORACLE_HOME Upgrade Mode -> ${neworaclehome}." >> ${LOG}

      export cmd="export ORACLE_HOME=${neworaclehome}; export ORACLE_SID=${db}; echo -e 'startup mount;' | ${neworaclehome}/bin/sqlplus '/ as sysdba'"
      echo "Running...... ${cmd}"
      echo "Running...... ${cmd}" >> ${LOG}
      ssh -n ${nodename} ${cmd} >> ${LOG}

      # Check is issue with last command
      if [ $? -eq 0 ]; then
         echo "Oracle database instance ${db} on ${nodename} Started"
         echo "Oracle database instance ${db} on ${nodename} Started" >> ${LOG}
      else
         echo "Oracle database instance ${db} on ${nodename} Start Failed, aborting....."
         echo "Oracle database instance ${db} on ${nodename} Start Failed, aborting....." >> ${LOG}
         exit 8
      fi

      # Put in if there is an encryption wallet that is not auto open
      #echo "--" >> ${LOG}
      #echo "Open Wallet for ${db} on ${nodename}"
      #echo "Open Wallet for ${db} on ${nodename}" >> ${LOG}
      #export cmd="export ORACLE_HOME=${neworaclehome}; export ORACLE_SID=${db}; echo 'alter system set encryption wallet open identified by \"<password>\" ;' | $ORACLE_HOME/bin/sqlplus '/ AS SYSDBA'"
      #ssh -n ${nodename} ${cmd} >> ${LOG}

      # open database in upgrade mode
      echo "--" >> ${LOG}
      echo "Open Database Upgrade for ${db} on ${nodename}"
      echo "Open Database Upgrade for ${db} on ${nodename}" >> ${LOG}
      export cmd="export ORACLE_HOME=${neworaclehome}; export ORACLE_SID=${db}; echo 'alter database open upgrade ;' | ${neworaclehome}/bin/sqlplus '/ AS SYSDBA'"
      echo "Running...... ${cmd}"
      echo "Running...... ${cmd}" >> ${LOG}
      ssh -n ${nodename} ${cmd} >> ${LOG}
   
      # Check execution of Open Upgrade
      if [ $? -eq 0 ]; then
         echo "Oracle instance ${db} on ${nodename} is in upgrade state, continuing"
         echo "Oracle instance ${db} on ${nodename} is in upgrade state, continuing" >> ${LOG}
      else
         echo "Oracle instance ${instname} on ${nodename} is not in upgrade state, aborting process"
         echo "Oracle instance ${instname} on ${nodename} is not in upgrade state, aborting process" >> ${LOG}
         exit 8
      fi
   
      # Execute the datapatch
      echo "Running datapatch for ${db} on ${nodename}"
      echo "Running datapatch for ${db} on ${nodename}" >> ${LOG}
      export cmd="export ORACLE_HOME=${neworaclehome}; export ORACLE_SID=${db}; ${neworaclehome}/OPatch/datapatch -verbose"
      echo "Running...... ${cmd}"
      echo "Running...... ${cmd}" >> ${LOG}
      ssh -n ${nodename} ${cmd} >> ${LOG}
   
      # Check execution of instance/db state was successful
      if [ $? -eq 0 ]; then
         echo "datapatch on ${nodename} for instance ${db} was successful." 
         echo "datapatch on ${nodename} for instance ${db} was successful."  >> ${LOG}
      else
         echo "datapatch on ${nodename} for instance ${db} was not successful." 
         echo "datapatch on ${nodename} for instance ${db} was not successful."  >> ${LOG}
         exit 8
      fi 
   
      # Shutdown instance so we can open it back up normal post datapatch
      echo "--" >> ${LOG}
      echo "DataPatch Completed, Shutdown for ${db} on ${nodename}"
      echo "DataPatch Completed, Shutdown for ${db} on ${nodename}" >> ${LOG}   
      export cmd="export ORACLE_HOME=${neworaclehome}; export ORACLE_SID=${db}; echo 'shutdown immediate' | ${neworaclehome}/bin/sqlplus '/ AS SYSDBA'"
      echo "Running...... ${cmd}"
      echo "Running...... ${cmd}" >> ${LOG}
      ssh -n ${nodename} ${cmd} >> ${LOG}

      # Check execution of Shutdown
      if [ $? -eq 0 ]; then
         echo "Shutdown for ${db} on ${nodename} ok, continuing"
         echo "Shutdown for ${db} on ${nodename} ok, continuing" >> ${LOG}
      else
         echo "Shutdown for ${db} on ${nodename} not ok, aborting process"
         echo "Shutdown for ${db} on ${nodename} not ok, aborting process" >> ${LOG}
         exit 8
      fi

      echo "Starting normal non-RAC instance ${db} on ${nodename} in new ORACLE_HOME -> ${neworaclehome}"
      echo "Starting normal non-RAC instance ${db} on ${nodename} in new ORACLE_HOME -> ${neworaclehome}" >> ${LOG}
      export cmd="export ORACLE_HOME=${neworaclehome}; export ORACLE_SID=${db}; echo 'startup' | ${neworaclehome}/bin/sqlplus '/ as sysdba'" 
      echo "Running...... ${cmd}"
      echo "Running...... ${cmd}" >> ${LOG}
      ssh -n ${nodename} ${cmd} >> ${LOG}
		 
      # Check execution of instance/db state was successful
      if [ $? -eq 0 ]; then
         echo "Oracle instance ${db} on ${nodename} is started, continuing"
         echo "Oracle instance ${db} on ${nodename} is started, continuing" >> ${LOG}
      else
         echo "Oracle instance ${db} on ${nodename} did not start, aborting process"
         echo "Oracle instance ${db} on ${nodename} did not start, aborting process" >> ${LOG}
         exit 8
      fi 
   else
      echo "Starting normal non-RAC Standby Instance ${db} on ${nodename} to Mount State in new ORACLE_HOME -> ${neworaclehome}"
      echo "Starting normal non-RAC Standby Instance ${db} on ${nodename} to Mount State in new ORACLE_HOME -> ${neworaclehome}" >> ${LOG}
      export cmd="export ORACLE_HOME=${neworaclehome}; export ORACLE_SID=${db}; echo 'startup mount;' | ${neworaclehome}/bin/sqlplus '/ as sysdba'" 
      echo "Running...... ${cmd}"
      echo "Running...... ${cmd}" >> ${LOG}
      ssh -n ${nodename} ${cmd} >> ${LOG}
		 
      # Check execution of instance/db state was successful
      if [ $? -eq 0 ]; then
         echo "Oracle instance ${db} on ${nodename} is started, continuing"
         echo "Oracle instance ${db} on ${nodename} is started, continuing" >> ${LOG}
      else
         echo "Oracle instance ${db} on ${nodename} did not start, aborting process"
         echo "Oracle instance ${db} on ${nodename} did not start, aborting process" >> ${LOG}
         exit 8
      fi 
   fi

   # Specified to sleep and wait for number of seconds   
   sleep 30
done < "${inputfile}"

#################################################################
# Run any scripts put in the post patch execution file
if [ -f "${SCRIPTLOC}/${dbpatchupdatepostexec}" ]
 then
echo "Running Post Patch Processes as defined in ${dbpatchupdatepostexec}"
echo "Running Post Patch Processes as defined in ${dbpatchupdatepostexec}" >> ${LOG}
while read -r line_script
do
    ssh -n ${nodename} ${line_script}
done < "${SCRIPTLOC}/${dbpatchupdatepostexec}"
fi

echo "#######################################################################################################################"
echo "#######################################################################################################################" >> ${LOG}
echo "ORACLE_HOME Switch for all Databases Complete."
echo "ORACLE_HOME Switch for all Databases Complete." >> ${LOG}

exit 0
