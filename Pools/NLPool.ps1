﻿param(
    [Parameter(Mandatory = $true)]
    [String]$Querymode = $null,
    [Parameter(Mandatory = $false)]
    [PSCustomObject]$Info
)

#. .\..\Include.ps1

$Name = (Get-Item $script:MyInvocation.MyCommand.Path).BaseName
$ActiveOnManualMode = $true
$ActiveOnAutomaticMode = $true
$ActiveOnAutomatic24hMode = $true
$WalletMode = 'Wallet'
$ApiUrl = 'https://nlpool.nl/api'
$MineUrl = 'mine.nlpool.nl'
$Location = 'EU'
$RewardType = "PPS"
$Result = @()

if ($Querymode -eq "Info") {
    $Result = [PSCustomObject]@{
        Disclaimer               = "Autoexchange to BTC/LTC, No registration"
        ActiveOnManualMode       = $ActiveOnManualMode
        ActiveOnAutomaticMode    = $ActiveOnAutomaticMode
        ActiveOnAutomatic24hMode = $ActiveOnAutomatic24hMode
        ApiData                  = $true
        WalletMode               = $WalletMode
        RewardType               = $RewardType
    }
}

if ($Querymode -eq "Speed") {
    $Request = Invoke-APIRequest -Url $($ApiUrl + "/walletEx?address=" + $Info.user) -Retry 1

    if ($Request) {
        $Result = $Request.Miners | ForEach-Object {
            [PSCustomObject]@{
                PoolName   = $Name
                Version    = $_.version
                Algorithm  = Get-AlgoUnifiedName $_.Algo
                WorkerName = (($_.password -split 'ID=')[1] -split ',')[0]
                Diff       = $_.difficulty
                Rejected   = $_.rejected
                HashRate   = $_.accepted
            }
        }
        Remove-Variable Request
    }
}

if ($Querymode -eq "Wallet") {
    $Request = Invoke-APIRequest -Url $($ApiUrl + "/wallet?address=" + $Info.user) -Retry 3

    if ($Request) {
        $Result = [PSCustomObject]@{
            Pool     = $Name
            Currency = $Request.currency
            Balance  = $Request.balance
        }
        Remove-Variable Request
    }
}

if ($Querymode -eq "Core") {
    $Request = Invoke-APIRequest -Url $($ApiUrl + "/status") -Retry 3
    $RequestCurrencies = Invoke-APIRequest -Url $($ApiUrl + "/currencies") -Retry 3
    if (-not $Request) {
        Write-Warning "$Name API NOT RESPONDING...ABORTING"
        Exit
    }

    $Currency = if ($Config.("Currency_" + $Name)) {$Config.("Currency_" + $Name)} else {$Config.Currency}

    if (
        @('BTC', 'LTC') -notcontains $Currency -and
        -not ( $RequestCurrencies -and ($RequestCurrencies | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | Where-Object { $_ -eq $Currency }))
    ) {
        Write-Warning "$Name $Currency may not be supported for payment"
    }

    if (-not $Wallets.$Currency) {
        Write-Warning "$Name $Currency wallet not defined"
        Exit
    }

    $Result = $Request | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | Where-Object {
        $Request.$_.HashRate -gt 0
    } | ForEach-Object {

        $Algo = $Request.$_
        $Pool_Algo = Get-AlgoUnifiedName $Algo.name

        $Divisor = 1000000 * $Algo.mbtc_mh_factor

        [PSCustomObject]@{
            Algorithm             = $Pool_Algo
            Info                  = $Pool_Algo
            Price                 = [decimal]$Algo.estimate_current / $Divisor
            Price24h              = [decimal]$Algo.estimate_last24h / $Divisor
            Actual24h             = [decimal]$Algo.actual_last24h / 1000 / $Divisor
            Protocol              = "stratum+tcp"
            Host                  = $MineUrl
            Port                  = $Algo.port
            User                  = $Wallets.$Currency
            Pass                  = "c=$Currency,ID=#WorkerName#"
            Location              = $Location
            SSL                   = $false
            Symbol                = Get-CoinSymbol -Coin $Pool_Algo
            ActiveOnManualMode    = $ActiveOnManualMode
            ActiveOnAutomaticMode = $ActiveOnAutomaticMode
            PoolWorkers           = $Algo.workers
            PoolHashRate          = $Algo.HashRate
            WalletMode            = $WalletMode
            WalletSymbol          = $Currency
            PoolName              = $Name
            Fee                   = $Algo.fees / 100
            RewardType            = $RewardType
        }
    }
    Remove-Variable Request
}

$Result
Remove-Variable Result
