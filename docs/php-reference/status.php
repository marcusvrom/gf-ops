<?php
include('config.php');

$loginSocket = @fsockopen($server_host, $login_port, $err, $err, 1);
$gatewaySocket = @fsockopen($server_host, $gateway_port, $err, $err, 1);
$ticketsocket = @fsockopen($server_host, $ticket_port, $err, $err, 1);

$characters_result = pg_query($db_gs, 'SELECT COUNT(*) FROM player_characters');
$num_characters = pg_fetch_result($characters_result, 0, 0);

$accounts_result = pg_query($db_ls, 'SELECT COUNT(*) FROM accounts');
$num_accounts = pg_fetch_result($accounts_result, 0, 0);

?>

<!DOCTYPE html>
<html lang='en'>

<head>
    <title> Grand Fantasia | Status </title>
    <meta http-equiv='content-type' content='text/html' ; charset='UTF-8' />
</head>

<body>
    <center>
        <br>
        <input type='button' value='Back' onclick="window.location.href='index.php'" />
        <br>
        <h3> Grand Fantasia Status </h3>
        <br>
        <?php
        if (!$loginSocket && !$gatewaySocket && !$ticketsocket) {
            echo "Server Global Status: <font color='red'>Offline</font><br><br>";
        } else {
            echo "Server Status: <font color='green'>Online</font><br><br>";
        }

        if (!$loginSocket) {
            echo "LoginServer: <font color='red'>Offline</font><br>";
        } else {
            echo "LoginServer: <font color='green'>Online</font><br>";
            fclose($loginSocket);
        }

        if (!$gatewaySocket) {
            echo "GatewayServer: <font color='red'>Offline</font><br>";
        } else {
            echo "GatewayServer: <font color='green'>Online</font><br>";
            fclose($gatewaySocket);
        }

        if (!$ticketsocket) {
            echo "TicketServer: <font color='red'>Offline</font><br>";
        } else {
            echo "TicketServer: <font color='green'>Online</font><br>";
            fclose($ticketsocket);
        }

        echo "<br>Registered Accounts: $num_accounts";
        echo "<br>Characters Created: $num_characters";
        ?>
    </center>
</body>

</html>