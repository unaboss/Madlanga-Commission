# Launch the Commission Research Tool
$rbin = "C:\Program Files\R\R-4.6.1\bin"
$workdir = "C:\Users\mabek\Documents\Madlanga comission\commission_research\app"
Set-Location -LiteralPath $workdir
& "$rbin\R.exe" -e "shiny::runApp(launch.browser=TRUE)"
