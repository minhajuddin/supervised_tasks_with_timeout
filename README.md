# Sup

cutoff_time: time after which we kill all processes
response_time: time after which we send a response

  D1. Spawn n processes where n is number of suppliers
    and these n processes can spawn more processes
  D2. Kill all of them after cutoff time: 5 seconds
  D3. Respond earlier than 5 seconds if we are done earlier
  D4. Respond in 'response_time' if our processes have not finished in 'response_time'
    and kill all processes after 'cutoff_time'
