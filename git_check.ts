const command = new Deno.Command("git", {
  args: ["status"],
  cwd: "c:/Users/ACER/Downloads/tooltracker-backend",
});
const { stdout, stderr } = await command.output();
await Deno.writeFile("c:/Users/ACER/Downloads/tooltracker-backend/git_out.txt", stdout);
await Deno.writeFile("c:/Users/ACER/Downloads/tooltracker-backend/git_err.txt", stderr);
console.log("Git check complete.");
