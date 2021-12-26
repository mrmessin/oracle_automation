#######################################################################################################
# ora_deploy_opatch_batch_apply.sh
#
# Description: Run deploy one off patches process for each database in data list
#              for a nodes in node list
#
# Dependancies:  Process Assumes Oracle RAC and Rolling Update
#
#                ora_deploy_db_patch_update.txt  (${dbpatchupdatefile})  [ora_deploy_db_patch_update_{env}.txt]
#                    Text File containing the main directory where all patches will reside for Patching with Process
#                    Format:
#                      /u01/app/oracle/software/Qtr_2021Jul_19.12
#
#                ora_deploy_db_qtrpatch.txt  (${dbpatchfile}) [ora_deploy_db_qtrpatch_{env}.txt]
#                    Text file that contains the qtr patch locations for each patch to be applied for database home
#                    Format:
#                      /u01/app/oracle/software/Qtr_2021Jul_19.12/32900083/32876380 opatch oracle
#                      /u01/app/oracle/software/Qtr_2021Jul_19.12/32900083/32895426 opatchauto root
#
#                ora_deploy_db_qtrpatch_nodes_{env}.txt (${inputfile})
#                    Text File that Lists Nodes/Oracle Home to apply Patch(es) for
#                    Format:
#                          node ORACLE_HOME
#                          node ORACLE_HOME
#
#                ora_deploy_opatch_batch_rollback.txt [ora_deploy_opatch_batch_rollback_{env}.txt] ** Optional
#                     List of one off patches applied to the ORACLE_HOME that must be rolled back
#                     this can include patches that may not be applied they will show not present
#                     and check will pass that it is not applied to home and continue.
#                     If File Does not Exist will assume no One off Patches to rollback
#
#                ora_deploy_opatch_batch_apply.txt [ora_deploy_opatch_batch_apply_{env}.txt] ** Optional
#                     List of one-off patches subject to be applied during the patch process
#                     these address one-off issues and are to be applied after bundle patch is applied
#                     If File Does not Exist will assume no One off Patches to apply
#
#               All Instances for node must exist in the /etc/oratab for process to get ORACLE_HOME
#               The cluster dbname is the database name as identified in clusterware for RAC, 
#               if not present then assumes non-RAC
#               The Cluster dbname is important as it tends to be different between primary and standby 
#               clusters for database as name in cluster tends to be same as DB unique name.
#               The rolling will require non-use or very low use of the JAVAVM therefore must ensure services
#               Using JAVAVM are off or of low enough utization proces will not impact applications
#               Run on only one of the instances of all all instance homes are patched.
#               Ensure Order in file is the order that the rolling update needs to happen
#
# Is it Used, check all instances for rolling upgrade:
#     select count(*) from x$kglob where KGLOBTYP = 29 OR KGLOBTYP = 56;
# How much is it used:
#   select sess.service_name, sess.username,sess.program, count(*)
#   from
#   v$session sess,
#   dba_users usr,
#   x$kgllk lk,
#   x$kglob
#   where kgllkuse=saddr
#   and kgllkhdl=kglhdadr
#   and kglobtyp in (29,56)
#   and sess.user# = usr.user_id
#   and usr.oracle_maintained = 'N'      -- Omit 11.2.0.4
#   group by sess.service_name, sess.username, sess.program
#   order by sess.service_name, sess.username, sess.program;
#
# Parameters:    environment set to use for paramter files for example
#                pass value of dev and all file parameters become filename${env}.txt
#                if no value passed then filename is filename.txt
#
# Output:  <Script location on file system>/logs/ora_deploy_db_qtrpatch_<date>.log
#
# Execution:   From central deploy/monitor node
#                               /u01/app/oracle/scripts/ora_deploy_db_qtrpatch.sh
#                               or
#                               /u01/app/oracle/scripts/ora_deploy_db_qtrpatch.sh <env>
#######################################################################################################
#
####################################################################################
# Accept parameter for file designation for the environment set to use 
# If not provided the process will default to use ora_deploy_db_qtrpatch_nodes.txt
# if environment provided then it is ora_deploy_db_qtrpatch_nodes${envinputfile}.txt
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
export LOGFILE=ora_deploy_db_qtrpatch_${envinputfile}_${DTE}.log
export LOG=$LOGPATH/$LOGFILE

#####################################################
# Script Environment variables
#####################################################
# export the page list (Change as require for process notifications)
export PAGE_LIST=dbas@availity.com,dbas@realmed.com
export EMAIL_LIST=DBAs@availity.com

echo "#################################################################################################"
echo "#################################################################################################" >> ${LOG}
echo "Checking Parameters and files for Qtr Patch Update Process....."
echo "Checking Parameters and files for Qtr Patch Update Process....." >> ${LOG}

################################################################################################
# Configuration Files for datapatch apply for instances this is standard and not configurable
# is is a fixed list of nodes, instance and dbname to do the post datapatch operation
# the other files for pathfile and patupupdate file are also considered fix, but
# setting the environment variables to other file names will allow those files to be used
if [ "${envinputfile}" = "" ]
 then
   echo "No env designation provided defaulting"
   echo "No env designation provided defaulting" >> ${LOG}
   export inputfile=${SCRIPTLOC}/ora_deploy_db_qtrpatch_nodes.txt
   export dbpatchfile=ora_deploy_db_qtrpatch.txt
   export datapatchinputfile=ora_deploy_db_datapatch.txt
   export dbpatchupdatefile=ora_deploy_db_patch_update.txt
   export oneoffpatch_apply=ora_deploy_opatch_batch_apply.txt
   export oneoffpatch_rollback=ora_deploy_opatch_batch_rollback.txt
else
   echo "Env designation provided setting filenames with _${envinputfile}" 
   echo "Env designation provided setting filenames with _${envinputfile}" >> ${LOG}
   export inputfile=${SCRIPTLOC}/ora_deploy_db_qtrpatch_nodes_${envinputfile}.txt
   export dbpatchfile=ora_deploy_db_qtrpatch_${envinputfile}.txt
   export datapatchinputfile=ora_deploy_db_datapatch_${envinputfile}.txt
   export dbpatchupdatefile=ora_deploy_db_patch_update_${envinputfile}.txt
   export oneoffpatch_apply=ora_deploy_opatch_batch_apply_${envinputfile}.txt
   export oneoffpatch_rollback=ora_deploy_opatch_batch_rollback_${envinputfile}.txt
  
   # for one off patches if environment file does not exist can use default file 
   if [ ! -f "${oneoffpatch_apply}" ]
    then
      echo "One off Patch Apply file ${oneoffpatch_apply} Does Not Exist Defaulting to ora_deploy_opatch_batch_apply.txt"
      echo "One off Patch Apply file ${oneoffpatch_apply} Does Not Exist Defaulting to ora_deploy_opatch_batch_apply.txt" >> ${LOG}
      export oneoffpatch_apply=ora_deploy_opatch_batch_apply.txt
   fi 

   if [ ! -f "${oneoffpatch_rollback}" ]
    then
      echo "One off Patch Rollback file ${oneoffpatch_rollback} Does Not Exist Defaulting to ora_deploy_opatch_batch_apply.txt"
      echo "One off Patch Rollback file ${oneoffpatch_rollback} Does Not Exist Defaulting to ora_deploy_opatch_batch_apply.txt" >> ${LOG}
      export oneoffpatch_rollback=ora_deploy_opatch_batch_rollback.txt
   fi 


fi

################################################################
# Check Parameter is valid and files exist
################################################################
if [ ! -f "${inputfile}" ]
then
   echo "Node/home list file provided -> ${inputfile} does not exist can not process one off patch update(s)."
   echo "Node/home list file provided -> ${inputfile} does not exist can not process one off patch update(s)." >> ${LOG}
   exit 8
fi

if [ ! -f "${dbpatchfile}" ]
 then
   echo "Qtr Patch List File Does Not Exist -> ${dbpatchfile} can not process one off patch update(s)."
   echo "Qtr Patch List File Does Not Exist -> ${dbpatchfile} can not process one off patch update(s)." >> ${LOG}
   exit 8
fi

if [ ! -f "${datapatchinputfile}" ] 
 then
   echo "Data Patch List File Does Not Exist -> ${datapatchinputfile} can not process patch update(s)."
   echo "Data Patch List File Does Not Exist -> ${datapatchinputfile} can not process patch update(s)." >> ${LOG}
   exit 8
fi

if [ ! -f "${dbpatchupdatefile}" ] 
 then
   echo "Patch Base Location File Does Not Exist -> ${dbpatchupdatefile} can not process patch update(s)."
   echo "Patch Base Location File Does Not Exist -> ${dbpatchupdatefile} can not process patch update(s)." >> ${LOG}
   exit 8
fi

echo "#################################################################################################"
echo "#################################################################################################" >> ${LOG}
echo "Using the Following Parameter Files:"
echo "Using the Following Parameter Files:" >> ${LOG}
echo "Node and ORACLE_HOME List File -> ${inputfile}"
echo "Node and ORACLE_HOME List File -> ${inputfile}" >> ${LOG}
echo "Qtr Patch List File -> ${dbpatchfile}"
echo "Qtr Patch List File -> ${dbpatchfile}" >> ${LOG}
echo "Data Patch List File -> ${datapatchinputfile}"
echo "Data Patch List File -> ${datapatchinputfile}" >> ${LOG}
echo "Patch Base Location File -> ${dbpatchupdatefile}"
echo "Patch Base Location File -> ${dbpatchupdatefile}" >> ${LOG}
echo "One off Patch Apply List File -> ${oneoffpatch_apply}" 
echo "One off Patch Apply List File -> ${oneoffpatch_apply}" >> ${LOG}
echo "One off Patch Rollback List File -> ${oneoffpatch_rollback}" 
echo "One off Patch Rollback List File -> ${oneoffpatch_rollback}" >> ${LOG}

echo "#################################################################################################"
echo "#################################################################################################" >> ${LOG}
# Set Local hostname
export HOSTNAME=`hostname`
echo "Running Process from -> ${HOSTNAME}"
echo "Running Process from -> ${HOSTNAME}" >> ${LOG}

# Check if we have one off patches to rollback or apply if we do not then nothing to do end process
echo "Checking of we have patches to rollback or apply if we do not then nothing to do......"
echo "Checking of we have patches to rollback or apply if we do not then nothing to do......" >> ${LOG}
if [ ! -f "${oneoffpatch_apply}" ] 
 then
   if [ ! -f "${oneoffpatch_rollback}" ] 
    then
      echo "One off Patch Rollback List Files Do Not Exist -> ${oneoffpatch_rollback} and ${oneoffpatch_apply} can not process patch update(s)."
      echo "One off Patch Rollback List Files Do Not Exist -> ${oneoffpatch_rollback} and ${oneoffpatch_apply} can not process patch update(s)." >> ${LOG}
      exit 8
   fi
fi

echo "#################################################################################################"
echo "#################################################################################################" >> ${LOG}
echo "Running One Off DB Patch for each node/home in ${inputfile}"
echo "Running One Off DB Patch for each node/home in ${inputfile}" >> ${LOG}
cat ${inputfile}
cat ${inputfile} >> ${LOG}

# Set the PATCHLOCATION (Important to One off Patches)
export PATCHLOCATION=`cat ${SCRIPTLOC}/${dbpatchupdatefile}`
echo "Using Patch Base Location: ${PATCHLOCATION}"
echo "Using Patch Base Location: ${PATCHLOCATION}" >> ${LOG}

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
   # Generate list of running instances for the node in the ORACLE_HOME we are patching   
   ###############################################################################################
   # List of databases in cluster
   echo "--------------------------------------------------------------------------------------------------------"
   echo "--------------------------------------------------------------------------------------------------------" >> ${LOG}
   echo "Getting List of Databases for RAC Cluster"
   echo "Getting List of Databases for RAC Cluster" >> ${LOG}
   cmd="export ORACLE_HOME=${oraclehome}; ${oraclehome}/bin/srvctl config database"
   export dblist=`ssh -n ${nodename} ${cmd}`

   # Check is issue with last command
   if [ $? -eq 0 ]; then
      echo "List of Databases in RAC Cluster"
      echo "List of Databases in RAC Cluster" >> ${LOG}
      echo "${dblist}"
      echo "${dblist}" >> ${LOG}
   else
      echo "List of databases for ${nodename} did not succeed can not continue may not be a RAC Cluster..."
      echo "List of databases for ${nodename} did not succeed can not continue may not be a RAC Cluster..." >> ${LOG}
      exit 8
   fi

   # Seed instance list to nothing
   export running_instance_list=''

   echo "--------------------------------------------------------------------------------------------------------"
   echo "--------------------------------------------------------------------------------------------------------" >> ${LOG}
   
   if [ "${dblist}" = "" ]
    then
      echo "No Databases on Server ${nodename} Skipping Check for Runnning Instances"
      echo "No Databases on Server ${nodename} Skipping Check for Runnning Instances" >> ${LOG}
   else
      # Go through each database in cluster check is instance running on node being patched
      for dbname in ${dblist}
      do 
         echo "Checking if Status for ${dbname} on ${nodename}"
         echo "Checking if Status for ${dbname} on ${nodename}" >> ${LOG}

         # Check ORACLE_HOME for instance is our oracle home that we arer patching
         cmd="export ORACLE_HOME=${oraclehome}; ${oraclehome}/bin/srvctl config database -d ${dbname} | grep ${oraclehome}"
         export result=`ssh -n ${nodename} ${cmd}`

         # Check is issue with last command
         if [ $? -eq 0 ]; then
            echo ""
         else
            echo "Check for running instance on ${nodename} in ${oraclehome} Failed, aborting......"
            echo "Check for running instance on ${nodename} in ${oraclehome} Failed, aborting......" >> ${LOG}
            exit 8
         fi

         if [ "${result}" = "" ]
          then
            echo "Skipping Database ${dbname} not using the patching home ${oraclehome}"
            echo "Skipping Database ${dbname} not using the patching home ${oraclehome}" >> ${LOG}
         else
            # from that list check that there is a running instance on the node
            # loop through the database list for the cluster checking for instance on node
            cmd="export ORACLE_HOME=${oraclehome}; ${oraclehome}/bin/srvctl status database -d ${dbname} | grep 'is running on node ${nodename}'"
            export result=`ssh -n ${nodename} ${cmd}`

            # if not null then we have a running instance
            if [ "${result}" = "" ]; then
               # Skipping the instance on node not running there
               echo "Skipping Database ${dbname} for instance ${instancename} not running on node ${nodename}"
               echo "Skipping Database ${dbname} for instance ${instancename} not running on node ${nodename}" >> ${LOG}
            else  
               # Running instance for databse exists on node being patched.
               export instancename=`echo ${result}| awk '{print $2}'`

               echo "Recording instance ${instancename} for ${dbname} into nodes running instance list."
               echo "Recording instance ${instancename} for ${dbname} into nodes running instance list." >> ${LOG}

               # Instance ok then record in running instance list
               export running_instance_list=`echo -e "${running_instance_list}\n${dbname} ${instancename}"`
            fi
         fi
      done
   fi

   echo "Getting Running instance list succeeded"
   echo "Getting Running instance list succeeded" >> ${LOG}
   echo "${running_instance_list}"
   echo "${running_instance_list}" >> ${LOG}

   if [ "${running_instance_list}" = "" ]
    then
       echo "No Running Instances on Server ${nodename} No Instances to Shutdown"
       echo "No Running Instances on Server ${nodename} No Instances to Shutdown" >> ${LOG}
   else
      ###############################################################################################
      # Shutdown instances in instance list
      ###############################################################################################
      echo "--------------------------------------------------------------------------------------------------------"
      echo "--------------------------------------------------------------------------------------------------------" >> ${LOG}
      echo "Shutting down instances ${running_instance_list} on ${nodename}."
      echo "Shutting down instances ${running_instance_list} on ${nodename}." >> ${LOG}
      echo "${running_instance_list}"

      #Set the field separator to new line
      IFS=$'\n'

      for db in `echo -e "${running_instance_list}"`
      do
         export actiondbname=`echo ${db}| awk '{print $1}'`
         export actioninstancename=`echo ${db}| awk '{print $2}'`

         echo "Shutting down database ${actiondbname} instance ${actioninstancename} on ${nodename}"
         echo "Shutting down database ${actiondbname} instance ${actioninstancename} on ${nodename}" >> ${LOG}

         export cmd="export ORACLE_HOME=${oraclehome}; ${oraclehome}/bin/srvctl stop instance -d ${actiondbname} -i ${actioninstancename} -force"
         ssh -n ${nodename} ${cmd}

         # Check is issue with last command
         if [ $? -eq 0 ]; then
            echo "Oracle database ${actiondbname} for instance ${actioninstancename} on ${nodename} Shutdown"
            echo "Oracle database ${actiondbname} for instance ${actioninstancename} on ${nodename} Shutdown" >> ${LOG}
         else
            echo "Oracle database ${actiondbname} for instance ${actioninstancename} on ${nodename} Shutdown Failed, aborting....."
            echo "Oracle database ${actiondbname} for instance ${actioninstancename} on ${nodename} Shutdown Failed, aborting....." >> ${LOG}
            exit 8
         fi
      done 
   fi

   ###############################################################################################
   # Check if lsof is any processes run with files from ORACLE_HOME being patched
   ###############################################################################################
   echo "Checking if any files in the ORACLE_HOME - ${oraclehome} are in use......"
   echo "Checking if any files in the ORACLE_HOME - ${oraclehome} are in use......" >> ${LOG}
   cmd="lsof | grep ${oraclehome}"

   # Initialize result
   export result=""
   export result=`ssh -n ${nodename} ${cmd}` >> ${LOG}

   # Check the patch result check
   if [ "${result}" = "" ]; then
      echo "No Processes running with Files in ORACLE_HOME - ${oraclehome} will continue...."
      echo "No Processes running with Files in ORACLE_HOME - ${oraclehome} will continue...." >> ${LOG}
   else
      echo "Processes running with Files in ORACLE_HOME - ${oraclehome} Aborting...."
      echo "Processes running with Files in ORACLE_HOME - ${oraclehome} Aborting...." >> ${LOG}
      echo "Will Need to Restart all databases for ${nodename} before rerunning process"
      echo "Will Need to Restart all databases for ${nodename} before rerunning process" >> ${LOG}
      exit 8
   fi

   ###############################################################################################
   # Rollback All One Off Patches
   ###############################################################################################
   echo "#################################################################################################"
   echo "#################################################################################################" >> ${LOG}
   echo "Rolling Back One-Off Database Home Patches on ${nodename} for ORACLE_HOME ${oraclehome}"  
   echo "Rolling Back One-Off Database Home Patches on ${nodename} for ORACLE_HOME ${oraclehome}" >> ${LOG}
 
   # If file Exists then we have patches to rollback 
   if [ -f "${oneoffpatch_rollback}" ]
    then
      cat ${SCRIPTLOC}/${oneoffpatch_rollback}
      cat ${SCRIPTLOC}/${oneoffpatch_rollback} >> ${LOG}
      
      # Execute rollback process requires list of patch in file ora_deploy_opatch_batch_rollback_{env}.txt 
      # or default ora_deploy_opatch_batch_rollback.txt as list of patches to rollback
      #
      # go through each node in the list in the file and execute patch rollback for each patch to HOME
      while read -r line
      do
         # Set patch number from line in file
         export PATCHNUMBER=${line}

         echo "----------------------- ${PATCHNUMBER} -----------------------------------------------------"
         echo "----------------------- ${PATCHNUMBER} -----------------------------------------------------" >> ${LOG}
         echo "Rolling back Patch ${PATCHNUMBER} for ${oraclehome} on ${nodename}"
         echo "Rolling back Patch ${PATCHNUMBER} for ${oraclehome} on ${nodename}" >> ${LOG}
         cmd="export ORACLE_HOME=${oraclehome}; ${oraclehome}/OPatch/opatch rollback -id ${PATCHNUMBER} -silent"
         echo ${cmd}
         echo ${cmd} >> ${LOG}
         ssh -n ${nodename} ${cmd} >> ${LOG}

         echo "Checking status of Patch ${PATCHNUMBER} for ${oraclehome} on ${nodename}"
         echo "Checking status of Patch ${PATCHNUMBER} for ${oraclehome} on ${nodename}" >> ${LOG}
         cmd="export ORACLE_HOME=${oraclehome}; ${oraclehome}/OPatch/opatch lsinventory | grep ${PATCHNUMBER}"
         echo ${cmd}
         echo ${cmd} >> ${LOG}
      
         # Initialize result
         export result=""
         export result=`ssh -n ${nodename} ${cmd}` >> ${LOG}

         # Check the patch result check
         if [ "${result}" != "" ]; then
            echo "ERROR -> Patch Rollback Verification Failed for ${PATCHNUMBER} on ${nodename}"
            echo "ERROR -> Patch Rollback Verification Failed for ${PATCHNUMBER} on ${nodename}" >> ${LOG}
            #exit 8
         else
            echo "Patch Rollback Verified for patch ${PATCHNUMBER} for ${oraclehome} on ${nodename}"
            echo "Patch Rollback Verified for patch ${PATCHNUMBER} for ${oraclehome} on ${nodename}" >> ${LOG}
         fi
      done < "${SCRIPTLOC}/${oneoffpatch_rollback}"
   else
      echo "No One off Patch Rollback File Exists, Assuming no Off Patches need to be Rolled Back."
      echo "No One off Patch Rollback File Exists, Assuming no Off Patches need to be Rolled Back." >> ${LOG}
   fi

   ###############################################################################################
   # Apply All One Off Patches
   ###############################################################################################
   echo "#################################################################################################"
   echo "#################################################################################################" >> ${LOG}
   echo "Applying One-Off Database Home Patches on ${nodename} for ORACLE_HOME ${oraclehome}"  
   echo "Applying One-Off Database Home Patches on ${nodename} for ORACLE_HOME ${oraclehome}" >> ${LOG}
   
   # If file Exists then we have patches to rollback 
   if [ -f "${oneoffpatch_apply}" ]
    then
      cat ${SCRIPTLOC}/${oneoffpatch_apply}
      cat ${SCRIPTLOC}/${oneoffpatch_apply} >> ${LOG}

      # Execute apply process requires list of patch in file ora_deploy_opatch_batch_apply.txt as list of patches to apply
      #
      # go through each node in the list in the file and execute patch apply for each patch to HOME
      while read -r line
      do
         # Set patch number from line in file
         export PATCHNUMBER=${line}

         echo "----------------------- ${PATCHNUMBER} -----------------------------------------------------"
         echo "----------------------- ${PATCHNUMBER} -----------------------------------------------------" >> ${LOG}
         echo "Applying Patch ${PATCHNUMBER} for ${oraclehome} on ${nodename}"
         echo "Applying Patch ${PATCHNUMBER} for ${oraclehome} on ${nodename}" >> ${LOG}
         cmd="cd ${PATCHLOCATION}/${PATCHNUMBER}; ${oraclehome}/OPatch/opatch apply -silent -ocmrf /u01/app/oracle/software/ocm.rsp"
         echo ${cmd}
         echo ${cmd} >> ${LOG}
         ssh -n ${nodename} ${cmd} >> ${LOG}

         echo "Checking status of Patch ${PATCHNUMBER} for ${oraclehome} on ${nodename}"
         echo "Checking status of Patch ${PATCHNUMBER} for ${oraclehome} on ${nodename}" >> ${LOG}
         cmd="export ORACLE_HOME=${oraclehome}; ${oraclehome}/OPatch/opatch lsinventory | grep ${PATCHNUMBER}"
         echo ${cmd}
         echo ${cmd} >> ${LOG}

         # initialize result
         export result=""
         export result=`ssh -n ${nodename} ${cmd}` >> ${LOG}

         # Check the patch result check
         if [ "${result}" = "" ]; then
            echo "ERROR -> Patch Apply Not verified for patch ${PATCHNUMBER} for ${oraclehome} on ${nodename}"
            echo "ERROR -> Patch Apply Not verified for patch ${PATCHNUMBER} for ${oraclehome} on ${nodename}" >> ${LOG}
            #exit 8
         else
            echo "Patch Apply Verified for patch ${PATCHNUMBER} for ${oraclehome} on ${nodename}"
            echo "Patch Apply Verified for patch ${PATCHNUMBER} for ${oraclehome} on ${nodename}" >> ${LOG}
         fi
      done < "${SCRIPTLOC}/${oneoffpatch_apply}"
   else
      echo "No One off Patch Apply File Exists, Assuming no Off Patches need to be Applied."
      echo "No One off Patch Apply File Exists, Assuming no Off Patches need to be Applied." >> ${LOG}
   fi

   ###############################################################################################
   # Startup database instances on Node for ORACLE_HOME being patched
   # Assumes /etc/oratab is up to date and has instance names in there
   ###############################################################################################
   echo "#################################################################################################"
   echo "#################################################################################################" >> ${LOG}
   echo "Starting instances ${running_instance_list} on ${nodename}."
   echo "Starting instances ${running_instance_list} on ${nodename}." >> ${LOG}

   for db in ${running_instance_list}
   do
      export actiondbname=`echo ${db}| awk '{print $1}'`
      export actioninstancename=`echo ${db}| awk '{print $2}'`

      echo "Starting database ${actiondbname} instance ${actioninstancename}"
      echo "Starting database ${actiondbname} instance ${actioninstancename}" >> ${LOG}

      export cmd="export ORACLE_HOME=${oraclehome}; ${oraclehome}/bin/srvctl start instance -d ${actiondbname} -i ${actioninstancename}"
      ssh -n ${nodename} ${cmd} >> ${LOG}

      # Check is issue with last command
      if [ $? -eq 0 ]; then
         echo "Oracle database ${actiondbname} for instance ${actioninstance} on ${nodename} Started"
         echo "Oracle database ${actiondbname} for instance ${actioninstance} on ${nodename} Started" >> ${LOG}
      else
         echo "Oracle database ${actiondbname} for instance ${actioninstance} on ${nodename} Start Failed, aborting....."
         echo "Oracle database ${actiondbname} for instance ${actioninstance} on ${nodename} Start Failed, aborting....." >> ${LOG}
         exit 8
      fi
   done

   echo "--------------------------------------------------------------------------------------------------------"
   echo "--------------------------------------------------------------------------------------------------------" >> ${LOG}
   echo "ORACLE_HOME Patching for node ${nodename} for ORACLE_HOME ${oraclehome} Complete."
   echo "ORACLE_HOME Patching for node ${nodename} for ORACLE_HOME ${oraclehome} Complete." >> ${LOG}
   echo "--" >> ${LOG}
   echo "--" >> ${LOG}
   echo "--"
   echo "--"
   echo "--------------------------------------------------------------------------------------------------------"
   echo "--------------------------------------------------------------------------------------------------------" >> ${LOG}
   echo "Pausing for Period of time before moving to next node for services settlement"
   echo "Pausing for Period of time before moving to next node for services settlement" >> ${LOG}

   ###############################################################################################
   # If we want to shift services we could develop automated process to move services here
   # Otherwise services will shift when next instance is shutdown as part of RAC
   ###############################################################################################

   # Specified to sleep and wait for number of seconds   
   sleep 60
   #sleep 600
   #sleep 3600

done < "${inputfile}"

echo "***********************************************************************************************************************"
echo "***********************************************************************************************************************" >> ${LOG}
echo "ORACLE_HOME Patching for all ORACLE_HOMEs ${oraclehome} Complete."
echo "ORACLE_HOME Patching for all ORACLE_HOMEs ${oraclehome} Complete." >> ${LOG}

################################################################################################
# Once all Nodes are patched Execute the datapatch
################################################################################################
echo "#######################################################################################################################"
echo "#######################################################################################################################" >> ${LOG}
echo "Executing the Post Data Patch Process for environment Patched....."
echo "Executing the Post Data Patch Process for environment Patched....." >> ${LOG}
cat ${datapatchinputfile}
cat ${datapatchinputfile} >> ${LOG}

# go through each node in the list in the file and execute upgrade
while read -r line
do
   ########################################################
   # Assign the nodename and agent home for processing
   export nodename=`echo ${line}| awk '{print $1}' `
   export instname=`echo ${line}| awk '{print $2}' `
   export racdbname=`echo ${line}| awk '{print $3}' `

   #########################################################################################
   # Set dbhome for instance on node and run datapatch from OPATCH location for instance
   export cmd="/usr/local/bin/dbhome ${instname}"
   export ORACLE_HOME=`ssh -n ${nodename} ${cmd} `

   # Check ORACLE_HOME is set
   if [ $? -eq 0 ]; then
      echo "Oracle HOME for ${nodename} - ${instname} is ${ORACLE_HOME}"
      echo "Oracle HOME for ${nodename} - ${instname} is ${ORACLE_HOME}" >> ${LOG}
   else
      echo "Oracle HOME for ${nodename} - ${instname} could not be determined, aborting process"
      echo "Oracle HOME for ${nodename} - ${instname} could not be determined, aborting process" >> ${LOG}
      exit 8
   fi

   # If there is a custom glogin.sql that must be moved out of the way for datapatch -verbose execution or it will fail
   export cmd="mv ${ORACLE_HOME}/sqlplus/admin/glogin.sql ${ORACLE_HOME}/sqlplus/admin/glogin.sql.save"
   ssh -n ${nodename} ${cmd} >> ${LOG}

   # If there is an issue sometimes post patch where the sqlpatch does not have execute permissions 
   # so need to fix for datapatch to run
   export cmd="chmod 775 ${ORACLE_HOME}/sqlpatch/sqlpatch"
   ssh -n ${nodename} ${cmd} >> ${LOG}
   
   ################################################################################################
   # Check if Database Instance is running, it needs to be running and open for process to work.
   export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; echo -ne 'set head off\n set pagesize 0\n select open_mode from v\$database;' | $ORACLE_HOME/bin/sqlplus -s '/ AS SYSDBA'"
   export result=`ssh -n ${nodename} ${cmd} `
   #echo "${result}" >> ${LOG}

   if [ "${result}" != "READ WRITE" ]
    then
       echo "Database is not Open READ WRITE, can not continue with datapatch, exiting skipping database......"
       echo "Database is not Open READ WRITE, can not continue with datapatch, exiting skipping database......" >> ${LOG}
       #exit 8
   else 
      echo "--------------------------------------------------------------------------------------------------------"
      echo "--------------------------------------------------------------------------------------------------------" >> ${LOG}
      echo "Executing the Datapatch for ${instname} on ${nodename}"
      echo "Executing the Datapatch for ${instname} on ${nodename}" >> ${LOG}

      ################################################################################################
      # Execute the datapatch This assumes being done rolling
      echo "Running datapatch for ${instname} on ${nodename}"
      echo "Running datapatch for ${instname} on ${nodename}" >> ${LOG}
      export cmd="export ORACLE_HOME=${ORACLE_HOME}; export ORACLE_SID=${instname}; $ORACLE_HOME/OPatch/datapatch -verbose -skip_upgrade_check"
      ssh -n ${nodename} ${cmd} >> ${LOG}

      # Check execution of instance/db state was successful
      if [ $? -eq 0 ]; then
         echo "datapatch on ${nodename} for instance ${instname} was successful."
         echo "datapatch on ${nodename} for instance ${instname} was successful."  >> ${LOG}
      else
         echo "datapatch on ${nodename} for instance ${instname} was not successful."
         echo "datapatch on ${nodename} for instance ${instname} was not successful."  >> ${LOG}
         exit 8
      fi
   fi

   # If there is a custom glogin.sql that must be moved out of the way for datapatch -verbose execution or it will fail
   export cmd="mv ${ORACLE_HOME}/sqlplus/admin/glogin.sql.save ${ORACLE_HOME}/sqlplus/admin/glogin.sql"
   ssh -n ${nodename} ${cmd} >> ${LOG}
done < "${datapatchinputfile}"

echo "----------------------------------------------------------------------------------------------"
echo "----------------------------------------------------------------------------------------------" >> ${LOG}
echo "Datapatch for all nodes/instances in list from ${datapatchinpufile} successful."
echo "Datapatch for all nodes/instances in list from ${datapatchinpufile} successful." >> ${LOG}
echo "################################################################################################"
echo "################################################################################################" >> ${LOG}


echo "#######################################################################################################################"
echo "#######################################################################################################################" >> ${LOG}

echo "#######################################################################################################################"
echo "#######################################################################################################################" >> ${LOG}
echo "DB One Off Patch Update Process Complete!"
echo "DB One Off Patch Update Process Complete!" >> ${LOG}

exit 0
