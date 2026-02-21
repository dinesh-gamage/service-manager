1. credential manager is not using common crud/import/export functions and not checking existing items by name/title. fix that
2. validate aws vault manager also . make sure its using common functions.
3. in service manager, 1. for path give an option to select a path from finder. 2. use a default path as users home. so no need to give everytime
4. ec2 manager 
    - add new column, move edit /delete to that, keep the rest in current column
    - add restart button, we need to restart the instance and get the latest ip. take a look at here. /Users/dineshgamage/eutech/projects/lucy/internal-tools/ec2-restart/src for reference.
    - add option to manually trigger a health check , no need to persist it. just check on demand.
    - expand the details section by default.
5. when no module is selected, main area shows a welcom message and tiles to select a module. let's change this to act as a dashboard (i think this make sense given the name is DevDash :D) from each modules we can publish one or more widgets and render them in a dashboard. widgets will have a title(based on what widget displays) , content area(widget content) and a foolter(Module name with arrow > and clicking this will go to respective module). ex: 
    - in service manager , we can show a list of services in a widget with icon buttons (one at a time for quick actions) (start/stop)
    - credentials can show a summary like how many entries are there, may be by category 
    - ec2 manager will show a list of instances  - |group|instance name| ip | copy button |refetch button

    header area with logo and welcom message ,make is small, re-agange to make more space for widgets,  make it lookk good and modern.