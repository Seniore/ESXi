#Script to check all LUNs with voma
#Warning: not tested yet in production
#Use at own risk

IFS=$'\n'
for line in `esxcli storage vmfs extent list | grep vmhba`; do
	datastore=`echo $line | awk '{ print $1}'`
	lun=`echo $line | awk '{ print $4}'`
	result=`voma -m vmfs -f check -d /vmfs/devices/disks/$lun`
	errors=`echo $result | sed -e 's/.*Total Errors/Total Errors/'`
	echo $datastore $errors
done