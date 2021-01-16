param($pattern = '*.ts')
$numLines = 0;

get-childitem $pattern -recurse |
select-object -expandproperty FullName |
where-object { $_ -notmatch 'node_modules' -and $_ -notmatch 'ts_modules' -and $_ -notlike '*.d.ts' } |
foreach-object {
    $numLines += (get-content $_).Count;
}

Write-Host "$(get-location) has a total of $numlines lines of $pattern excluding node_modules, ts_modules, and .d.ts files."