<?xml version="1.0" encoding="UTF-8"?>
<ModuleFile xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
	<UiMod name="CPlusCrowdFilter" version="0.1" date="10/02/2026">

		<Author name="BrauneRatte" />
		<Description text="Filters for crowded places: hides the damage numbers of blue names, the object handles of all but enemies and your own pets, and the spell words overhead of whom you choose; and a light blue arrow over yourself" />

		<Dependencies>
			<Dependency name="ClfCommon" />
			<!--
				ClfDamageMod replaces DamageWindow.Init and ClfTextParse replaces
				OverheadText.ShowOverheadText in their own initialize. Depending
				on them makes this module initialize after them, so the wrappers
				installed here go round theirs.
			-->
			<Dependency name="ClfDamageMod" />
			<Dependency name="ClfTextParse" />
		</Dependencies>

		<Files>
			<File name="CPlusCrowdTexts.lua" />
			<File name="CPlusCrowdFilter.lua" />
		</Files>

		<OnInitialize>
			<CallFunction name="CPlusCrowdFilter.initialize" />
		</OnInitialize>

		<!--
			The arrow over the player is put on again every 2 seconds while it is on.
			ClfCommon.onUpdate calls a fixed list of modules, so the module asks for
			its frames here. While the arrow is off, the call returns at once.
		-->
		<OnUpdate>
			<CallFunction name="CPlusCrowdFilter.onUpdate" />
		</OnUpdate>

		<OnShutdown>
			<CallFunction name="CPlusCrowdFilter.shutdown" />
		</OnShutdown>

	</UiMod>
</ModuleFile>
