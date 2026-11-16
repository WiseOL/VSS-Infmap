if SERVER then AddCSLuaFile() end
local savedReports=0
local function SaveReport(prefix, report)
    savedReports=savedReports+1
    file.CreateDir("infmap")
    local path = "infmap/" .. prefix .. "_" .. os.date("%Y%m%d_%H%M%S") .. "_" .. savedReports .. ".json"
    file.Write(path, util.TableToJSON(report, true))
    return "data/" .. path
end
if CLIENT then
    local capture
    hook.Add("PostRender", "ACF_InfMapClientProfile", function()
        if not capture then return end
        local dt=RealFrameTime()
        capture.frames=capture.frames+1
        capture.frameSeconds=capture.frameSeconds+dt
        capture.worstFrameMS=math.max(capture.worstFrameMS,dt*1000)
        capture.peakVisuals=math.max(capture.peakVisuals,ACF and ACF.InfMapActiveEffects or 0)
        capture.peakPending=math.max(capture.peakPending,ACF and ACF.InfMapPendingCount or 0)
    end)
    concommand.Add("acf_infmap_client_profile",function(_,_,args)
        if capture then print("[ACF profile] Client capture already running.") return end
        local seconds=args[1]==nil and 30 or tonumber(args[1])
        if not seconds or seconds~=seconds or seconds<1 or seconds>120 then print("Duration must be 1-120 seconds.") return end
        capture={frames=0,frameSeconds=0,worstFrameMS=0,peakVisuals=0,peakPending=0}
        timer.Simple(seconds,function()
            local report=capture capture=nil
            report.kind="client render frames; includes the entire game, not only ACF"
            report.averageFPS=report.frames/math.max(report.frameSeconds,0.000001)
            report.averageFrameMS=report.frameSeconds*1000/math.max(report.frames,1)
            print(string.format("[ACF profile] Client %.1f FPS, %.2f ms/frame, worst %.2f ms; visuals %d / pending %d. Saved %s",
                report.averageFPS,report.averageFrameMS,report.worstFrameMS,report.peakVisuals,report.peakPending,SaveReport("client_firing",report)))
        end)
        print("[ACF profile] Client capture started for "..seconds.." seconds.")
    end)
    return
end
local capture
local function Snapshot()
    local b=ACF.InfMapBallisticsMetrics or {}
    local t=InfMap.ACFTraceStats or {}
    local n=ACF.InfMapNetworkStats or {}
    return {time=SysTime(),ticks=engine.TickCount(),ballisticSeconds=b.seconds or 0,created=b.created or 0,
        traceSeconds=t.seconds or 0,rawSeconds=t.rawSeconds or 0,traces=t.calls or 0,segments=t.segments or 0,
        crossChunk=t.crossChunk or 0,bytes=n.bytes or 0,compact=n.compact or 0,generic=n.generic or 0,removals=n.removals or 0}
end
local function Delta(now, before)
    local out={} for key,value in pairs(now) do out[key]=value-before[key] end return out
end
local function Active()
    local count=0 for _ in pairs(ACF.Ballistics.Bullets) do count=count+1 end return count
end
local function Say(ply,message)
    if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE,"[ACF profile] "..message.."\n")
    else print("[ACF profile] "..message) end
end
local function Finish()
    if not capture then return end
    local run=capture capture=nil
    InfMap.ACFFireProfiling=run.previousFlag
    timer.Remove("ACF_InfMapFiringProfile")
    local totals=Delta(Snapshot(),run.start)
    local report={kind="server",totals=totals,samples=run.samples,peakSampledBullets=run.peak,
        notes="Ballistics includes creation/iteration; trace time includes gun/radar/camera scope and overlaps ballistics. Raw trace time is nested within trace time. Physics sample is engine-wide. Bytes are encoded compatibility payload, not per-recipient wire traffic."}
    report.ballisticMSPerTick=totals.ballisticSeconds*1000/math.max(totals.ticks,1)
    report.traceMSPerTick=totals.traceSeconds*1000/math.max(totals.ticks,1)
    report.rawTraceMSPerTick=totals.rawSeconds*1000/math.max(totals.ticks,1)
    report.observedTPS=totals.ticks/math.max(totals.time,0.000001)
    local path=SaveReport("server_firing",report)
    Say(run.owner,string.format("%.1fs: %.3f ballistic ms/tick | %.3f trace ms/tick (%.3f raw, overlapping) | %.1f TPS | sampled peak %d bullets | created %d | %.1f KiB encoded. Saved %s",
        totals.time,report.ballisticMSPerTick,report.traceMSPerTick,report.rawTraceMSPerTick,report.observedTPS,run.peak,totals.created,totals.bytes/1024,path))
end
concommand.Add("acf_infmap_profile",function(ply,_,args)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    local action=args[1] or "start"
    if action=="stop" then Finish() return end
    if action=="status" then Say(ply,capture and "Capture running." or "No capture running.") return end
    if action~="start" then Say(ply,"Usage: acf_infmap_profile start [seconds] | stop | status") return end
    if capture then Say(ply,"Capture already running.") return end
    if not InfMap or not ACF or not ACF.InfMapBallisticsMetrics or not ACF.Ballistics or not InfMap.ACFTraceStats then
        Say(ply,"InfMap/ACF profiling counters have not initialized.") return
    end
    local seconds=args[2]==nil and 30 or tonumber(args[2])
    if not seconds or seconds~=seconds or seconds<1 or seconds>120 then Say(ply,"Duration must be 1-120 seconds.") return end
    local start=Snapshot()
    capture={owner=ply,start=start,last=start,deadline=SysTime()+seconds,samples={},peak=Active(),previousFlag=InfMap.ACFFireProfiling}
    InfMap.ACFFireProfiling=true
    timer.Create("ACF_InfMapFiringProfile",1,0,function()
        if not capture then return end
        local now=Snapshot()
        local sample=Delta(now,capture.last)
        sample.active=Active()
        if physenv and physenv.GetLastSimulationTime then sample.physicsLastStepMS=physenv.GetLastSimulationTime()*1000 end
        capture.peak=math.max(capture.peak,sample.active)
        capture.samples[#capture.samples+1]=sample capture.last=now
        if now.time>=capture.deadline then Finish() end
    end)
    Say(ply,"Server capture started for "..seconds.." seconds. Fire normally; a report will be saved automatically.")
end)
