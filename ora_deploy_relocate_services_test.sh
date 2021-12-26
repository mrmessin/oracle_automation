#
####################################################################################
# Accept parameter for file designation for the environment set to use
# If not provided the process will default to use ora_deploy_db_qtrpatch_nodes.txt
# if environment provided then it is ora_deploy_db_qtrpatch_nodes$_{envinput}.txt
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
export LOGFILE=ora_deploy_services_relocation_test_${envinputfile}_${DTE}.log
export LOG=$LOGPATH/$LOGFILE

#####################################################
# Script Environment variables
#####################################################
# export the page list (Change as require for process notifications)
export PAGE_LIST=dbas@availity.com,dbas@realmed.com
export EMAIL_LIST=DBAs@availity.com

echo "###########################################################################################"
echo "###########################################################################################" >> ${LOG}
echo "Checking Parameters and files for Qtr Patch Update Process for testing service relocation....."
echo "Checking Parameters and files for Qtr Patch Update Process for testing service relocation....." >> ${LOG}

################################################################################################
# Configuration Files for datapatch apply for instances this is standard and not configurable
# is is a fixed list of nodes, instance and dbname to do the post datapatch operation
# the other files for pathfile and patupupdate file are also considered fix, but
# setting the environment variables to other file names will allow those files to be used
if [ "${envinputfile}" = "" ]
 then
   echo "No env designation provided defaulting"
   echo "No env designation provided defaulting" >> ${LOG}
   # GI
   export patchfile=${SCRIPTLOC}/ora_deploy_gi_qtrpatch.txt
   # GI/DB
   export inputfile=${SCRIPTLOC}/ora_deploy_gi_db_qtrpatch_nodes.txt
   # DB
   export dbpatchfile=${SCRIPTLOC}/ora_deploy_db_qtrpatch.txt
   export datapatchinputfile=${SCRIPTLOC}/ora_deploy_db_datapatch.txt
   export dbpatchupdatefile=${SCRIPTLOC}/ora_deploy_db_patch_update.txt
else
   echo "Env designation provided setting filenames with _${envinputfile}"
   echo "Env designation provided setting filenames with _${envinputfile}" >> ${LOG}
   #GI
   export patchfile=${SCRIPTLOC}/ora_deploy_gi_qtrpatch_${envinputfile}.txt
   # GI/DB
   export inputfile=${SCRIPTLOC}/ora_deploy_gi_db_qtrpatch_nodes_${envinputfile}.txt
   # DB
   export dbpatchfile=${SCRIPTLOC}/ora_deploy_db_qtrpatch_${envinputfile}.txt
   export datapatchinputfile=${SCRIPTLOC}/ora_deploy_db_datapatch_${envinputfile}.txt
   export dbpatchupdatefile=${SCRIPTLOC}/ora_deploy_db_patch_update_${envinputfile}.txt
fi

################################################################
# Check Parameter is valid and files exist
################################################################
########################
# GI Input Validation
########################
if [ -z "${patchfile}" ]
then
   echo "No Patch List File Provided ${patchfile} can not proceed with gi patching"
   echo "No Patch List File Provided ${patchfile} can not proceed with gi patching" >> ${LOG}
   exit 8
fi

###########################
# GI/DB Input Validation
###########################
if [ ! -f "${inputfile}" ]
then
   echo "Node/home list file provided -> ${inputfile} does not exist can not process GI/DB patch update."
   echo "Node/home list file provided -> ${inputfile} does not exist can not process GI/DB patch update." >> ${LOG}
   exit 8
fi

########################
# DB Input Validation
########################
if [ ! -f "${dbpatchfile}" ]
 then
   echo "Parameter File Does Not Exist -> ${dbpatchfile} can not process qtr patch update."
   echo "Parameter File Does Not Exist -> ${dbpatchfile} can not process qtr patch update." >> ${LOG}
   exit 8
fi

if [ ! -f "${datapatchinputfile}" ]
 then
   echo "Parameter File Does Not Exist -> ${datapatchinputfile} can not process qtr patch update."
   echo "Parameter File Does Not Exist -> ${datapatchinputfile} can not process qtr patch update." >> ${LOG}
   exit 8
fi

if [ ! -f "${dbpatchupdatefile}" ]
 then
   echo "Parameter File Does Not Exist -> ${dbpatchupdatefile} can not process qtr patch update."
   echo "Parameter File Does Not Exist -> ${dbpatchupdatefile} can not process qtr patch update." >> ${LOG}
   exit 8
fi

if [ ! -f "${SCRIPTLOC}/ora_deploy_opatch_batch_rollback.txt" ]
 then
   echo "Parameter File Does Not Exist -> ${SCRIPTLOC}/ora_deploy_opatch_batch_rollback.txt can not process qtr patch update."
   echo "Parameter File Does Not Exist -> ${SCRIPTLOC}/ora_deploy_opatch_batch_rollback.txt can not process qtr patch update." >> ${LOG}
   exit 8
fi

if [ ! -f "${SCRIPTLOC}/ora_deploy_opatch_batch_apply.txt" ]
 then
   echo "Parameter File Does Not Exist -> ${SCRIPTLOC}/ora_deploy_opatch_batch_apply.txt can not process qtr patch update."
   echo "Parameter File Does Not Exist -> ${SCRIPTLOC}/ora_deploy_opatch_batch_apply.txt can not process qtr patch update." >> ${LOG}
   exit 8
fi

echo "#################################################################################################"
echo "Using the Following Parameter Files:"
echo "Using the Following Parameter Files:" >> ${LOG}
echo "Node/Home List File -> ${inputfile}"
echo "Node/Home List File -> ${inputfile}" >> ${LOG}
echo "GI Patch File -> ${patchfile}"
echo "GI Patch File -> ${patchfile}" >> ${LOG}
echo "DB Patch File -> ${dbpatchfile}"
echo "DB Patch File -> ${dbpatchfile}" >> ${LOG}
echo "DataPatch File -> ${datapatchinputfile}"
echo "DataPatch File -> ${datapatchinputfile}" >> ${LOG}
echo "DataPatch Update File -> ${dbpatchupdatefile}"
echo "DataPatch Update File -> ${dbpatchupdatefile}" >> ${LOG}
echo "One-Off Rollback Patch List File -> ora_deploy_opatch_batch_rollback.txt"
echo "One-Off Rollback Patch List File -> ora_deploy_opatch_batch_apply.txt"

# Set Local hostname
export HOSTNAME=`hostname`
echo ${HOSTNAME}
echo ${HOSTNAME} >> ${LOG}

echo "#################################################################################################"
echo "#################################################################################################" >> ${LOG}
echo "Running GI Patching and DB Patching for each node/home in ${inputfile}"
echo "Running GI Patching and DB Patching for each node/home in ${inputfile}" >> ${LOG}
cat ${inputfile}
cat ${inputfile} >> ${LOG}
echo "-"

# Set the DBONEOFFPATCHLOCATION (Important to One off Patches)
export DBONEOFFPATCHLOCATION=`cat ${SCRIPTLOC}/${dbpatchupdatefile}`
echo "DB One Off Patch Base Location -> ${DBONEOFFPATCHLOCATION}"
echo "DB One Off Patch Base Location -> ${DBONEOFFPATCHLOCATION}" >> ${LOG}

# We are Just starting at first node (can set for non-prod to N so only 60 second pause)
export first_node="Y"

# go through each node in the list in the file and execute upgrade
while read -r line
do
   ########################################################
   # Assign the nodename and agent home for processing
   export nodename=`echo ${line}| awk '{print $1}'`
   export gioraclehome=`echo ${line}| awk '{print $2}'`
   export dboraclehome=`echo ${line}| awk '{print $3}'`

   echo "#################################################################################################"
   echo "#################################################################################################" >> ${LOG}
   echo "Processing GI Oracle HOME for ${nodename} - ${gioraclehome}"
   echo "Processing GI Oracle HOME for ${nodename} - ${gioraclehome}" >> ${LOG}
   echo "Processing DB Oracle HOME for ${nodename} - ${dboraclehome}"
   echo "Processing DB Oracle HOME for ${nodename} - ${dboraclehome}" >> ${LOG}

   echo "Getting List of Databases for RAC Cluster for DB ORACLE_HOME ${dboraclehome}"
   echo "Getting List of Databases for RAC Cluster for DB ORACLE_HOME ${dboraclehome}" >> ${LOG}
   cmd="export ORACLE_HOME=${dboraclehome}; ${dboraclehome}/bin/srvctl config database"
   export dblist=`ssh -n ${nodename} ${cmd}`

   # Check if issue with last command
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

   ###############################################################################################
   # Generate list of running instances for the node in the DB ORACLE_HOME we are patching
   # We want to shut these down prior to beginning patching so that way they are down and
   # We can move from GI Patch to database patch immediately and not have instances
   # come back up post GI Patching
   ###############################################################################################
   # List of databases in cluster
   echo "--------------------------------------------------------------------------------------------------------"
   echo "--------------------------------------------------------------------------------------------------------" >> ${LOG}
   echo "Getting List of Databases for RAC Cluster for DB ORACLE_HOME ${dboraclehome}"
   echo "Getting List of Databases for RAC Cluster for DB ORACLE_HOME ${dboraclehome}" >> ${LOG}
   cmd="export ORACLE_HOME=${dboraclehome}; ${dboraclehome}/bin/srvctl config database"
   export dblist=`ssh -n ${nodename} ${cmd}`

   # Check if issue with last command
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
      echo "No Running Databases on Server ${nodename} Skipping Check for Runnning Instances"
      echo "No Running Databases on Server ${nodename} Skipping Check for Runnning Instances" >> ${LOG}
   else
      # Go through each database in cluster check is instance running on node being patched
      for dbname in ${dblist}
      do
         echo "Checking if Status for ${dbname} on ${nodename}"
         echo "Checking if Status for ${dbname} on ${nodename}" >> ${LOG}

         # Check ORACLE_HOME for instance is our oracle home that we arer patching
         cmd="export ORACLE_HOME=${dboraclehome}; ${dboraclehome}/bin/srvctl config database -d ${dbname} | grep ${dboraclehome}"
         export result=`ssh -n ${nodename} ${cmd}`

         # Check is issue with last command
         if [ $? -eq 0 ]; then
            echo ""
         else
            echo "Check for running instance on ${nodename} in ${dboraclehome} Failed, aborting......"
            echo "Check for running instance on ${nodename} in ${dboraclehome} Failed, aborting......" >> ${LOG}
            exit 8
         fi

         if [ "${result}" = "" ]
          then
            echo "Skipping Database ${dbname} not using the patching home ${dboraclehome}"
            echo "Skipping Database ${dbname} not using the patching home ${dboraclehome}" >> ${LOG}
         else
            # from that list check that there is a running instance on the node
            # loop through the database list for the cluster checking for instance on node
            cmd="export ORACLE_HOME=${dboraclehome}; ${dboraclehome}/bin/srvctl status database -d ${dbname} | grep 'is running on node ${nodename}'"
            export result=`ssh -n ${nodename} ${cmd}`

            # if not null then we have a running instance
            if [ "${result}" = "" ]; then
               # Skipping the instance on node not running there
               echo "Skipping Database ${dbname} not running on node ${nodename}"
               echo "Skipping Database ${dbname} not running on node ${nodename}" >> ${LOG}
            else
               # Running instance for databse exists on node being patched.
               export instancename=`echo ${result}| awk '{print $2}'`

               echo "Recording instance ${instancename} for ${dbname} into nodes running instance list."
               echo "Recording instance ${instancename} for ${dbname} into nodes running instance list." >> ${LOG}

               # Instance ok then record in running instance list
               export running_instance_list=`echo -e "${running_instance_list}\n${dbname} ${instancename}"`
			   
			   ################################################################################################################
			   # Put in Services Relocation Here!!!
			   # Check for services running on instance to be patch as it is a running instance on the host
			   
			   cmd="export ORACLE_HOME=${dboraclehome}; ${dboraclehome}/bin/srvctl status service -d ${dbname} | grep ${instancename} | awk '{print $2}'"
			   export services_list=`ssh -n ${nodename} ${cmd}`
			   
               # Check is issue with last command
               if [ $? -eq 0 ]; then
                  echo ""
               else
			      echo "Check for Services for running instance ${instancename} failed.  Aborting......"
				  echo "Check for Services for running instance ${instancename} failed.  Aborting......" >> ${LOG}
				  exit 8
               fi
			   
			   if [ "${services_list}" = "" ]; then
			      echo "No Services running for instancename that needs to be relocated, skipping....."
				  echo "No Services running for instancename that needs to be relocated, skipping....." >> ${LOG}
			   else
			      # For each service in the list relocate the service
			      for servicename in ${services_list}
			      do
					 cmd="export ORACLE_HOME=${dboraclehome}; ${dboraclehome}/bin/srvctl config service -d ${dbname} -s ${servicename} | grep "Available instances" | awk '{print $3}'"
					 export availableserviceinstance=`ssh -n ${nodename} ${cmd}`
					 
					 if [ $? -eq 0 ]; then
                        echo ""
                     else
			           echo "Check for Service ${servicename} relocation to a running instance failed.  Aborting......"
				       echo "Check for Service ${servicename} relocation to a running instance failed.  Aborting......" >> ${LOG}
					   exit 8
                     fi
					 
					 if [ "${availableserviceinstance}" = "" ]; then
					     echo "Check to Move Service ${servicename} from ${instancename} to an Available Instance Failed.  Aborting....."
						 echo "Check to Move Service ${servicename} from ${instancename} to an Available Instance Failed.  Aborting....." >> ${LOG}
						 exit 8
					 else
			            echo "Relocating Service ${servicename} from ${instancename} to ${availableserviceinstance}"
						echo "Relocating Service ${servicename} from ${instancename} to ${availableserviceinstance}" >> ${LOG}
						
						cmd="export ORACLE_HOME=${dboraclehome}; ${dboraclehome}/bin/srvctl relocate service -d ${dbname} -s ${servicename} -i ${instancename} -t ${availableserviceinstance}"
						ssh -n ${nodename} ${cmd}
						
						if [ $? -eq 0 ]; then
                           echo ""
                        else
			              echo "Relocate Service ${servicename} relocation to a running instance ${availableserviceinstance} failed.  Aborting......"
				          echo "Relocate Service ${servicename} relocation to a running instance ${availableserviceinstance} failed.  Aborting......" >> ${LOG}
					      exit 8
                        fi
					 fi
			      done
                 
				  export services_relocated="Y"
			   fi
               # End Put in Services Relocate Code
  			   ################################################################################################################
			fi
         fi
      done
   fi

   echo "Getting Running instance list for ${nodename} and relocate services succeeded"

   # If we relocated services sleep for 10 min otherwise we can continue normally
   if [ "${services_relocated}" = "Y" ]; then
      echo "Services Had to be Relocated Pasuing for 10 minutes......."
	  echo "Services Had to be Relocated Pasuing for 10 minutes......." >> ${LOG}
      sleep 600
   fi
   
done

echo "Completed Services Relocation Test"
echo "Completed Services Relocation Test" >> ${LOG}
   
exit 0
