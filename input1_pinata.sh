#!/bin/bash
rm -rf /home/pin/portal/7.5/apps/quest/offshore_work/end_end_account1/results  
input="/home/pin/portal/7.5/sys/test/input_records.csv"
# Set "," as the field separator using $IFS 
# and read line by line using while read combo
while IFS=',' read -r f1 f2 f3 f4 
do
  echo "$f1 $f2 $f3 $f4"

export f1
export f2
export f3
export f4
cd /home/pin/portal/7.5/apps/quest/offshore_work/end_end_account1
echo "Pinata Starting"
pinata charter-test.pin
done < /home/pin/portal/7.5/sys/test/input_records.csv
cd /home/pin/portal/7.5/apps/quest/offshore_work/end_end_account1/results
cat create_* | grep 'BA_ACCOUNT_NO\|BA_BILLINFO_ID\|BA_LN\|BA_FN' > list.txt
awk '{print $1}''{print $2}''{print $3}' ORS=' '  list.txt | sed 's/"//g'
#while IFS='=' read f1 f2 f3 f4
#     do   echo "Field   : $f1"
#          echo "Value   : $f2"
#done < list.txt
cat create_* | grep 'Pass' | tr -s " " | cut -d ' ' -f2,5,7 > list1.txt
while IFS=' ' read -r f1 f2 f3
do echo "Field=$f1 --> Actual Value=$f2 --> Expected value=$f3"
if [[ "$f1" = "PIN_FLD_LAST_NAME" || "$f1" = "PIN_FLD_FIRST_NAME" ]]
then
        if [ "$f2" = "$f3" ]
        then
                echo "Account Created Successfully"
		else
		echo "Account Creation Failed"
        fi
fi
done < list1.txt
