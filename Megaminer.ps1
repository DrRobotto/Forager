#--------------optional parameters...to allow direct launch without prompt to user
param(
    [Parameter(Mandatory = $false)]
    [String]$MiningMode = $null#= "AUTOMATIC/MANUAL"
    #[String]$MiningMode = "MANUAL"
    ,
    [Parameter(Mandatory = $false)]
    [string]$PoolsName = $null
    #[string]$PoolsName = "YIIMP"
    ,
    [Parameter(Mandatory = $false)]
    [string]$CoinsName = $null
    #[string]$CoinsName ="decred"
)

. .\Include.ps1

#check parameters

if (($MiningMode -eq "MANUAL") -and ($PoolsName.count -gt 1)) { write-host ONLY ONE POOL CAN BE SELECTED ON MANUAL MODE}


#--------------Load config.txt file

$Currency= get_config_variable "CURRENCY"
$Location = get_config_variable "LOCATION"
$LocalCurrency = get_config_variable "LOCALCURRENCY"
if ($LocalCurrency.length -eq 0) {
    #for old config.txt compatibility
    switch ($location) {
        'Europe' {$LocalCurrency = "EUR"}
        'US' {$LocalCurrency = "USD"}
        'ASIA' {$LocalCurrency = "USD"}
        'GB' {$LocalCurrency = "GBP"}
        default {$LocalCurrency = "USD"}
    }
}

$CoinsWallets = @{} #needed for anonymous pools load
((Get-Content config.txt | Where-Object {$_ -like '@@WALLET_*=*'}) -replace '@@WALLET_*=*', '').TrimEnd() | ForEach-Object {$CoinsWallets.add(($_ -split "=")[0], ($_ -split "=")[1])}


$SelectedOption = ""

#-----------------Ask user for mode to mining AUTO/MANUAL to use, if a pool is indicated in parameters no prompt

Clear-Host
write-host ..............................................................................................
write-host ...................SELECT MODE TO MINE.....................................................
write-host ..............................................................................................

$Modes = @()
$Modes += [pscustomobject]@{"Option" = 0; "Mode" = 'AUTOMATIC'; "Explanation" = 'Not necesary choose coin to mine, program choose more profitable coin based on pool´s current statistics'}
$Modes += [pscustomobject]@{"Option" = 1; "Mode" = 'AUTOMATIC24h'; "Explanation" = 'Same as Automatic mode but based on pools/WTM reported last 24h profit'}
$Modes += [pscustomobject]@{"Option" = 2; "Mode" = 'MANUAL'; "Explanation" = 'You select coin to mine'}

$Modes | Format-Table Option, Mode, Explanation  | out-host


If ($MiningMode -eq "") {
    $SelectedOption = Read-Host -Prompt 'SELECT ONE OPTION:'
    $MiningMode = $Modes[$SelectedOption].Mode
    write-host SELECTED OPTION::$MiningMode
} else
{write-host SELECTED BY PARAMETER OPTION::$MiningMode}




#-----------------Ask user for pool/s to use, if a pool is indicated in parameters no prompt

switch ($MiningMode) {
    "Automatic" {$Pools = Get_Pools -Querymode "Info" | Where-Object ActiveOnAutomaticMode -eq $true | sort name }
    "Automatic24h" {$Pools = Get_Pools -Querymode "Info" | Where-Object ActiveOnAutomatic24hMode -eq $true | sort name }
    "Manual" {$Pools = Get_Pools -Querymode "Info" | Where-Object ActiveOnManualMode -eq $true | sort name }
}

$Pools | Add-Member Option "0"
$counter = 0
$Pools | ForEach-Object {
    $_.Option = $counter
    $counter++}


if ($MiningMode -ne "Manual") {
    $Pools += [pscustomobject]@{"Disclaimer" = ""; "ActiveOnManualMode" = $false; "ActiveOnAutomaticMode" = $true; "ActiveOnAutomatic24hMode" = $true; "name" = 'ALL POOLS'; "option" = 99}
}


#Clear-Host
write-host ..............................................................................................
write-host ...................SELECT POOL/S  TO MINE.....................................................
write-host ..............................................................................................

$Pools | Format-Table Option, name, disclaimer | out-host



If (($PoolsName -eq "") -or ($PoolsName -eq $null)) {


    if ($MiningMode -eq "manual") {
        $SelectedOption = Read-Host -Prompt 'SELECT ONE OPTION:'
        while ($SelectedOption -like '*,*') {
            $SelectedOption = Read-Host -Prompt 'SELECT ONLY ONE OPTION:'
        }
    }
    if ($MiningMode -ne "Manual") {
        $SelectedOption = Read-Host -Prompt 'SELECT OPTION/S (separated by comma):'
        if ($SelectedOption -eq "99") {
            $SelectedOption = ""
            $Pools | Where-Object Option -ne 99 | ForEach-Object {
                if ($SelectedOption -eq "") {$comma = ''} else {$comma = ','}
                $SelectedOption += $comma + $_.Option
            }
        }

    }
    $SelectedOptions = $SelectedOption -split ','
    $PoolsName = ""
    $SelectedOptions |ForEach-Object {
        if ($PoolsName -eq "") {$comma = ''} else {$comma = ','}
        $PoolsName += $comma + $Pools[$_].name
    }

    $PoolsName = ('#' + $PoolsName) -replace '# ,', '' -replace ' ', '' -replace '#', '' #In test mode this is not necesary, in real execution yes...??????

    write-host SELECTED OPTION:: $PoolsName
} else {
    write-host SELECTED BY PARAMETER ::$PoolsName
}



#-----------------Ask user for coins----------------------------------------------------


if ($MiningMode -eq "manual") {

    If ($CoinsName -eq "") {

        #Load coins for pool´s file
        if ($SelectedPool.ApiData -eq $false)
        {write-host        POOL API NOT EXISTS, SOME DATA NOT AVAILABLE!!!!!}
        else
        {write-host CALLING POOL API........}



        $CoinsPool = Get_Pools -Querymode "Menu" -PoolsFilterList $PoolsName -location $Location |Select-Object info, symbol, algorithm, Workers, PoolHashRate, Blocks_24h -unique | Sort-Object info

        $CoinsPool | Add-Member Option "0"
        $CoinsPool | Add-Member YourHashRate ([Double]0.0)
        $CoinsPool | Add-Member BTCPrice ([Double]0.0)
        $CoinsPool | Add-Member BTCChange24h ([Double]0.0)
        $CoinsPool | Add-Member DiffChange24h ([Double]0.0)
        $CoinsPool | Add-Member Reward ([Double]0.0)
        $CoinsPool | Add-Member BtcProfit ([Double]0.0)
        $CoinsPool | Add-Member LocalProfit ([Double]0.0)
        $CoinsPool | Add-Member LocalPrice ([Double]0.0)



        $ManualMiningApiUse = $true
        # (Get-Content config.txt | Where-Object {$_ -like '@@MANUALMININGAPIUSE=*'} ) -replace '@@MANUALMININGAPIUSE=', ''




        if ($ManualMiningApiUse -eq $true) {
            try {
                write-host CALLING WHATTOMINE API.........
                $WTMResponse = Invoke-WebRequest "https://whattomine.com/coins.json" -UseBasicParsing -TimeoutSec 3 | ConvertFrom-Json | Select-Object -ExpandProperty coins
                write-host CALLING BITTREX API............
                $BTXResponse = (Invoke-WebRequest "https://bittrex.com/api/v1.1/public/getmarketsummaries" -TimeoutSec 5| ConvertFrom-Json|Select-Object -ExpandProperty result)
                write-host CALLING COINDESK API............
                $CDKResponse = Invoke-WebRequest "https://api.coindesk.com/v1/bpi/currentprice/$LocalCurrency.json" -UseBasicParsing -TimeoutSec 3 | ConvertFrom-Json | Select-Object -ExpandProperty BPI
                write-host CALLING CoinMarketCap API............
                $CMCResponse = Invoke-WebRequest "https://api.coinmarketcap.com/v1/ticker/?limit=0" -UseBasicParsing -TimeoutSec 3 | ConvertFrom-Json
            } catch {}
        }

        $Counter = 0
        $CoinsPool | ForEach-Object {
            $_.Option = $Counter
            $counter++
            $_.YourHashRate = (Get-Best-Hashrate-Algo $_.Algorithm).hashrate

            if ($ManualMiningApiUse -eq $true -and $_.symbol -ne "" -and $_.symbol -ne $null) {

                #Get data from bittrex global api call
                if ($BTXResponse -ne $null) {
                    foreach ($BtxCoin in $BTXResponse)
                    {if ($BtxCoin.marketname -eq ("btc-" + $_.symbol)) {  $_.BTCPrice = $BtxCoin.Last}}
                }

                if ($CMCResponse -ne $null) {
                    foreach ($CMCCoin in $CMCResponse)
                    {if ($CMCCoin.Symbol -eq $_.symbol) {  $_.BTCPrice = $CMCCoin.price_btc}}
                }

                #If no data try with CRYPTOPIA
                if ($_.BTCPrice -eq 0) {
                    $ApiResponse = $null
                    "CALLING CRYPTOPIA API........" + $_.symbol + "_BTC" | out-Host
                    try {
                        $Apicall = "https://www.cryptopia.co.nz/api/GetMarket/" + $_.symbol + '_BTC'
                        $ApiResponse = (Invoke-WebRequest $ApiCall -UseBasicParsing  -TimeoutSec 2| ConvertFrom-Json|Select-Object -ExpandProperty data)
                    } catch {}

                    if ($ApiResponse -ne $null) {
                        $_.BTCPrice = $ApiResponse.LastPrice
                        #$_.BTCChange24h=$ApiResponse.Change
                    }
                }


                #Data from WTM
                if ($WTMResponse -ne $null) {
                    $WtmCoin = $WTMResponse.($_.Info)
                    if ($WtmCoin -ne $null) {

                        if ($WtmCoin.difficulty24 -ne 0) {$_.DiffChange24h = (1 - ($WtmCoin.difficulty / $WtmCoin.difficulty24)) * 100}
                        $WTMFactor = get_WhattomineFactor $_.Algorithm

                        if ($WTMFactor -ne $null) {
                            $_.Reward = [double]([double]$WtmCoin.estimated_rewards * ([double]$_.YourHashRate / [double]$WTMFactor))
                            $_.BtcProfit = [double]([double]$WtmCoin.Btc_revenue * ([double]$_.YourHashRate / [double]$WTMFactor))
                        }
                    }
                }

                $_.LocalProfit = $CDKResponse.$LocalCurrency.rate_float * [double]$_.BtcProfit
                $_.LocalPrice = $CDKResponse.$LocalCurrency.rate_float * [double]$_.BtcPrice
            }
        }

        Clear-Host
        write-host ....................................................................................................
        write-host ............................SELECT COIN TO MINE.....................................................
        write-host ....................................................................................................

        #Only one pool is allowed in manual mode at this point
        $SelectedPool = $Pools | where name -eq $PoolsName

        if ($SelectedPool.ApiData -eq $false) {write-host        ----POOL API NOT EXISTS, SOME DATA NOT AVAILABLE---}

        $LabelPrice = "$LocalCurrency" + "Price"
        $LabelProfit = "$LocalCurrency" + "Profit"
        $localBTCvalue = $CDKResponse.$LocalCurrency.rate_float

        $CoinsPool  | Format-Table -Wrap (
            @{Label = "Opt."; Expression = {$_.Option}; Align = 'right'} ,
            @{Label = "Name"; Expression = {$_.info.toupper()}; Align = 'left'} ,
            @{Label = "Symbol"; Expression = {$_.symbol}; Align = 'left'},
            @{Label = "Algorithm"; Expression = {$_.algorithm.tolower()}; Align = 'left'},
            # @{Label = "Workers"; Expression = {$_.Workers}; Align = 'right'},
            # @{Label = "PoolHash"; Expression = {"$($_.PoolHashRate | ConvertTo-Hash)/s"}; Align = 'right'},
            @{Label = "HashRate"; Expression = {(ConvertTo_Hash ($_.YourHashRate)) + "/s"}; Align = 'right'},
            # @{Label = "Blocks_24h"; Expression = {$_.Blocks_24h}; Align = 'right'},
            @{Label = "BTCPrice"; Expression = {if ($_.BTCPrice -gt 0) {[math]::Round($_.BTCPrice, 6).ToString("n6")}}; Align = 'right'},
            @{Label = $LabelPrice; Expression = { [math]::Round($_.LocalPrice, 2)}; Align = 'right'},
            # @{Label = "DiffChange24h"; Expression = {([math]::Round($_.DiffChange24h,1)).ToString()+'%'}; Align = 'right'},
            @{Label = "Reward"; Expression = {if ($_.Reward -gt 0 ) {[math]::Round($_.Reward, 3)}}; Align = 'right'},
            @{Label = "mBTCProfit"; Expression = {if ($_.BtcProfit -gt 0 ) {($_.BtcProfit * 1000).ToString("n5")}}; Align = 'right'},
            @{Label = $LabelProfit; Expression = {if ($_.LocalProfit -gt 0 ) {[math]::Round($_.LocalProfit, 2)}}; Align = 'right'}
        )  | out-host


        $SelectedOption = Read-Host -Prompt 'SELECT ONE OPTION:'
        while ($SelectedOption -like '*,*') {
            $SelectedOption = Read-Host -Prompt 'SELECT ONLY ONE OPTION:'
        }
        $CoinsName = $CoinsPool[$SelectedOption].Info -replace '_', ',' #for dual mining
        $AlgosName = $CoinsPool[$SelectedOption].Algorithm -replace '_', ',' #for dual mining

        write-host SELECTED OPTION:: $CoinsName - $AlgosName
    } else {

        write-host SELECTED BY PARAMETER :: $CoinsName
    }


}


#-----------------Launch Command
$command = "./core.ps1 -MiningMode $MiningMode -PoolsName $PoolsName"
if ($MiningMode -eq "manual") {
    $command += " $(if ($CoinsName.Length -gt 0) {"-Coinsname $CoinsName"}) -Algorithm $AlgosName"
}

#write-host $command
Invoke-Expression $command

