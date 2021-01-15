$output = docker ps;

if($output.length -gt 1) {
    $nonHeaderLines = $output[1..$output.length];
    foreach($line in $nonHeaderLines) {
        $tokens = -split $line;
        $inspectionJson = docker inspect $tokens[0] # the first token in docker ps output is the container id.
        $inspectionJson | convertfrom-json -depth 99;
    }
}
else { 
    # if there are no running containers, just return an empty array.
    @();
}