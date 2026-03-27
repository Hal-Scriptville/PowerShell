Get-ADComputer -Filter * -Properties lastlogontimestamp  | select name,distinguishedname,@{ n

= "LastLogonDate"; e = { [datetime]::FromFileTime( $_.lastLogonTimestamp ) } } | ogv