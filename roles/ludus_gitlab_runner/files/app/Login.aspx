<%@ Page Language="C#" %>
<%@ Import Namespace="System.Data.SqlClient" %>
<%@ Import Namespace="System.Configuration" %>
<script runat="server">
  protected void btnLogin_Click(object sender, EventArgs e)
  {
    string connStr = ConfigurationManager.ConnectionStrings["ThruntOps"].ConnectionString;
    // Vulnerable: unsanitized string concatenation — SQL injection
    string query = "SELECT * FROM Users WHERE username='" + txtUsername.Text
                 + "' AND password='" + txtPassword.Text + "'";
    try
    {
      using (SqlConnection conn = new SqlConnection(connStr))
      {
        conn.Open();
        SqlCommand cmd = new SqlCommand(query, conn);
        SqlDataReader reader = cmd.ExecuteReader();
        if (reader.HasRows)
        {
          reader.Read();
          lblResult.ForeColor = System.Drawing.Color.Green;
          lblResult.Text = "Login successful. Welcome, " + reader["username"] + " ("
                         + reader["role"] + ")";
        }
        else
        {
          lblResult.ForeColor = System.Drawing.Color.Red;
          lblResult.Text = "Invalid username or password.";
        }
      }
    }
    catch (Exception ex)
    {
      // Debug mode: full exception exposed — aids error-based SQLi
      lblResult.ForeColor = System.Drawing.Color.DarkRed;
      lblResult.Text = "Error: " + ex.Message;
    }
  }
</script>
<!DOCTYPE html>
<html>
<head>
  <title>ThruntOps — Employee Login</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 40px; background: #f4f4f4; }
    h2 { color: #333; }
    .form-row { margin: 8px 0; }
    label { display: inline-block; width: 90px; }
    input[type=text], input[type=password] { width: 200px; padding: 4px; }
    .result { margin-top: 14px; font-weight: bold; }
    a { font-size: 13px; color: #666; }
  </style>
</head>
<body>
  <h2>Employee Login</h2>
  <form runat="server">
    <div class="form-row">
      <label>Username:</label>
      <asp:TextBox ID="txtUsername" runat="server" />
    </div>
    <div class="form-row">
      <label>Password:</label>
      <asp:TextBox ID="txtPassword" runat="server" TextMode="Password" />
    </div>
    <div class="form-row">
      <asp:Button ID="btnLogin" runat="server" Text="Login" OnClick="btnLogin_Click" />
    </div>
    <div class="result">
      <asp:Label ID="lblResult" runat="server" />
    </div>
  </form>
  <p><a href="Default.aspx">← Back to portal</a></p>
</body>
</html>
