<?php
include('config.php');

$message = '';

if (isset($_POST['submit'])) {
    $username = $_POST['username'];
    $ammount = $_POST['ammount'];
    if ($ammount > 99999) {
        $message = "Invalid Ammount: MAX: 99999";
    } else {

        $query = "SELECT pvalues FROM tb_user WHERE mid = '$username'";
        $result = pg_query($db_ms, $query);
        $row = pg_fetch_assoc($result);
        if (!$row) {
            $message = "<font color='red'>ACCOUNT '$username' NOT FOUND</font>";
        } else {
            $ammount += $row['pvalues'];

            $query = "UPDATE tb_user SET pvalues = $ammount WHERE mid = '$username'";
            $result = pg_query($db_ms, $query);

            if ($result) {
                $message = "<font color='green'>SUCCESS! NEW AMMOUNT: $ammount</font>";
            } else {
                $message = "<font color='red'>ERROR!</font>";
            }
        }
    }
}
?>

<!DOCTYPE html>
<html lang='en'>

<head>
    <title> Grand Fantasia | Add AP </title>
    <meta http-equiv='content-type' content='text/html' ; charset='UTF-8' />
</head>

<body>
    <center>
        <br>
        <input type='button' value='Back' onclick="window.location.href='index.php'" />
        <br>
        <h3> Grand Fantasia Add AP </h3>
        <br>
        <form action="<?= $_SERVER['PHP_SELF']; ?>" method='post'>
            <label for='username'>Account:</label>
            <input type='text' id='username' name='username'>
            <br>
            <label for="ammount">Ammount (max: 99999):</label>
            <input type="number" id="ammount" name="ammount" min="0" max="99999"><br><br>
            <br>
            <input type='submit' name='submit' value='Add AP'>
        </form>
        <p><?php echo $message;
            ?></p>
    </center>
</body>

</html>