function Start-RabbitMqListener {
    <#
    .SYNOPSIS
        Start a RabbitMq listener

    .DESCRIPTION
        Start a RabbitMq listener that runs until you break execution

    .PARAMETER ComputerName
        RabbitMq host

        If SSL is specified, we use this as the SslOption server name as well.

    .PARAMETER Exchange
        RabbitMq Exchange

    .PARAMETER Key
        Routing Key to look for

        If you specify a QueueName and no Key, we use the QueueName as the key

    .PARAMETER QueueName
        If specified, bind to this queue.

        If not specified, create a temporal queue

    .PARAMETER Durable
        If queuename is specified, this needs to match whether it is durable

        See Get-RabbitMQQueue

    .PARAMETER Exclusive
        If queuename is specified, this needs to match whether it is Exclusive

        See Get-RabbitMQQueue

    .PARAMETER AutoDelete
        If queuename is specified, this needs to match whether it is AutoDelete

        See Get-RabbitMQQueue

    .PARAMETER LoopInterval
        Seconds. Timeout for each interval we wait for a RabbitMq message. Defaults to 1 second.

    .PARAMETER Credential
        Optional PSCredential to connect to RabbitMq with

    .PARAMETER Ssl
        Optional Ssl version to connect to RabbitMq with

        If specified, we use ComputerName as the SslOption ServerName property.
    
    .EXAMPLE
        Start-RabbitMqListener -ComputerName RabbitMq.Contoso.com -Exchange MyExchange -Key 'wat' -Credential $Credential -Ssl Tls12

        # Connect to RabbitMq.contoso.com over Tls 1.2 with credentials in $Credential
        # Listen for new messages on MyExchange exchange, with routing key 'wat'
    #>
	param(
        [string]$ComputerName = $Script:RabbitMqConfig.ComputerName,

		[parameter(Mandatory = $True)]
        [string]$Exchange,

        [parameter(ParameterSetName = 'NoQueueName',Mandatory = $true)]
        [parameter(ParameterSetName = 'QueueName',Mandatory = $false)]
        [string]$Key,

        [parameter(ParameterSetName = 'QueueName',
                   Mandatory = $True)]
        [string]$QueueName,

        [parameter(ParameterSetName = 'QueueName')]
        [bool]$Durable = $true,

        [parameter(ParameterSetName = 'QueueName')]
        [bool]$Exclusive = $False,

        [parameter(ParameterSetName = 'QueueName')]
        [bool]$AutoDelete = $False,

        [int]$LoopInterval = 1,

        [PSCredential]$Credential,

        [System.Security.Authentication.SslProtocols]$Ssl
	)
	try
    {
        #Build the connection
        $Params = @{ComputerName = $ComputerName }
        if($Ssl) { $Params.Add('Ssl',$Ssl) }
        if($Credential) { $Params.Add('Credential',$Credential) }
        $Connection = New-RabbitMqConnectionFactory @Params
		
		$Channel = $Connection.CreateModel()
		
		#Create a personal queue or bind to an existing queue
        if($QueueName)
        {
            $QueueResult = $Channel.QueueDeclare($QueueName, $Durable, $Exclusive, $AutoDelete, $null)
            if(-not $Key)
            {
                $Key = $QueueName
            }
        }
        else
        {
            $QueueResult = $Channel.QueueDeclare()
        }
		
		#Bind our queue to the ServerBuilds exchange
		$Channel.QueueBind($QueueResult.QueueName, $Exchange, $Key)
		
		#Create our consumer
		$Consumer = New-Object RabbitMQ.Client.QueueingBasicConsumer($Channel)
		$Channel.BasicConsume($QueueResult.QueueName, $True, $Consumer) > $Null
		
		$Delivery = New-Object RabbitMQ.Client.Events.BasicDeliverEventArgs
		
		#Listen on an infinite loop but still use timeouts so Ctrl+C will work!
		$Timeout = New-TimeSpan -Seconds $LoopInterval
		$Message = $null
		while($true)
        {
			if($Consumer.Queue.Dequeue($Timeout.TotalMilliseconds, [ref]$Delivery))
            {
				ConvertFrom-RabbitMqDelivery -Delivery $Delivery
				#$Channel.BasicAck($Delivery.DeliveryTag, $false)
			}
		}
	}
    finally
    {
		if($Channel)
        {
			$Channel.Close()
		}
		if($Connection -and $Connection.IsOpen)
        {
			$Connection.Close()
		}
	}
}
