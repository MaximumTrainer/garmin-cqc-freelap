<settings>
    <setting propertyKey="@Properties.course1" title="Course 1 (S:0;L:30;F:100)">
        <settingConfig type="alphaNumeric"/>
    </setting>
    <setting propertyKey="@Properties.course2" title="Course 2">
        <settingConfig type="alphaNumeric"/>
    </setting>
    <setting propertyKey="@Properties.course3" title="Course 3">
        <settingConfig type="alphaNumeric"/>
    </setting>
    <setting propertyKey="@Properties.activeCourse" title="Active course">
        <settingConfig type="list">
            <listEntry value="1">Course 1</listEntry>
            <listEntry value="2">Course 2</listEntry>
            <listEntry value="3">Course 3</listEntry>
        </settingConfig>
    </setting>
    <setting propertyKey="@Properties.bleLatencyMs" title="BLE latency estimate (ms)">
        <settingConfig type="numeric" min="0" max="2000"/>
    </setting>
    <setting propertyKey="@Properties.clearAfterWrite" title="Clear split fields after write">
        <settingConfig type="boolean"/>
    </setting>
    <setting propertyKey="@Properties.lapPerCrossing" title="Garmin lap on every crossing">
        <settingConfig type="boolean"/>
    </setting>
    <setting propertyKey="@Properties.captureMode" title="Capture mode (raw packets)">
        <settingConfig type="boolean"/>
    </setting>
</settings>
