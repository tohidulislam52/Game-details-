# Receive কমানোর রিপোর্ট

Oct 29, 2026 · @Tohidul

আপনার গেমে একটা বড় ভুল স্ক্রিপ্ট নেই, যেটা একা 50–60 KB/s পাঠাচ্ছে। Receive আসছে কয়েকটা উৎস মিলিয়ে: এক সার্ভারে ৫০–৬০ জন প্লেয়ারের অ্যাভাটার আর অ্যানিমেশন, সার্ভারে অনবরত নড়া physics জিনিস, admin কমান্ড, আর join-এর সময় বিশাল ডাউনলোড। নিচে প্রতিটার জায়গা আর সমাধান দেওয়া হলো।

ভিত্তি: `Bangladeshi_Tower_41.rbxl` আর আগের Developer Console স্ক্রিনশট (Recv গড়ে 50–55 KB/s, সার্ভারের মোট আউটপুট 1,147 KB/s)। গেম চালিয়ে মাপা সম্ভব হয়নি, তাই কোন উৎস কত KB/s তা নিচের পরীক্ষা দিয়ে মিলিয়ে নিতে হবে।

## এক নজরে

প্রভাব অনুযায়ী সাজানো। "প্রভাব" কোড আর সংখ্যা দেখে অনুমান; আসল KB/s পরীক্ষা করে মাপতে হবে।

| উৎস | কোথায় | প্রভাব | সমাধান |
| --- | --- | --- | --- |
| ৫০–৬০ জন প্লেয়ারের অ্যাভাটার, নাচ আর অ্যানিমেশন | Players.MaxPlayers = 60 | সবচেয়ে বেশি | MaxPlayers 35–40 করুন |
| দূরের জিনিসও আপডেট পায় | Workspace.StreamingTargetRadius = 500 | বেশি | 256 করে পরীক্ষা করুন |
| Admin troll কমান্ড (Disco, Spin, Drunk) | Admin Panel/AdminServer | চালু থাকলে খুব বেশি | বন্ধ করুন |
| ১৫টা প্রজাপতির ডানা physics-এ অনবরত ঘোরে | Workspace/Butterflies (RotateV) | মাঝারি | ক্লায়েন্টে নিন বা anchor করুন |
| গরু সারাক্ষণ হাঁটে | Workspace/Cow/cow | মাঝারি | ক্লায়েন্টে নিন |
| স্কোরবোর্ডের Dummy unanchored | FishingNPCS/FishLeaderboard/Dummy1 | কম | HumanoidRootPart anchor করুন |
| প্রতিটা প্লেয়ারকে join-এ বিশাল ডাউনলোড | ReplicatedStorage (12,405 instance), MaterialService (1,313 material) | join স্পাইক + ক্লায়েন্ট মেমোরি | অপ্রয়োজনীয় জিনিস সরান |
| টপ NPC-এ বারবার অ্যাভাটার বসানো | JamerLF RaisedBoard / DonateBoard (প্রতি ২০ s) | কম | বিক্রেতাকে বলুন বা সরিয়ে দিন |
| প্রতি সেকেন্ডে সবার PlayerGui-তে টাইমার লেখা | TableTopServer/TableLearboard | কম (তবে CPU বেশি) | টাইমার বাদ দিন |

## ১. প্লেয়ার সংখ্যা আর Streaming সেটিংস

আপনার Receive-এর সবচেয়ে বড় অংশ অন্য প্লেয়ারদের ক্যারেক্টার। প্রতিটা প্লেয়ারের অবস্থান, নাচের অ্যানিমেশন, বসা, টুল ধরা, সবই বাকি সবার কাছে যায়। ৫০ জন থাকলে একজন অন্য ৪৯ জনের ডেটা পায়, তাই প্লেয়ার বাড়লে Receive প্রায় সমান হারে বাড়ে। আপনার গেম মূলত hangout, যেখানে সবাই এক জায়গায় নাচে আর আড্ডা দেয়, তাই এই অংশটা স্বাভাবিকভাবেই বড়।

**কী করবেন:**

1. **MaxPlayers কমান।** ফাইলে 60, ড্যাশবোর্ডে 50 দেখায়। 35–40 করলে Receive আর সার্ভার মেমোরি দুটোই অনেক কমবে, আর Roblox বেশি সার্ভার খুলবে। সবচেয়ে সহজ আর সবচেয়ে বড় প্রভাব। (Creator Dashboard → Places → Access বা Studio-তে Game Settings → Places)
2. **StreamingTargetRadius 500 থেকে 256 করুন।** এটা বলে প্লেয়ারের চারপাশে কত দূর পর্যন্ত ম্যাপ আর নড়াচড়া পাঠানো হবে। কমালে দূরের জিনিসের আপডেট কম আসে, মোবাইলে মেমোরিও কমে। দূরের দৃশ্য খালি লাগলে 300–350 করুন। StreamingEnabled আগে থেকেই চালু আছে, এটা ভালো।
3. **নাচের অ্যানিমেশন ক্লায়েন্টে চালান।** প্লেয়ারের নিজের ক্যারেক্টারের অ্যানিমেশন LocalScript থেকে Play হলে Roblox কম ডেটায় সিঙ্ক করে। Dance/Sync আগে থেকেই এভাবে ক্লায়েন্টে চলে। CarryServer সার্ভার থেকে অ্যানিমেশন চালায়; কোলে নেওয়া কম হয় বলে এর প্রভাব ছোট।

## ২. সার্ভারে নড়াচড়া করা physics জিনিস

যে unanchored পার্ট সার্ভারে নড়ে, তার অবস্থান সেকেন্ডে অনেকবার কাছের সব প্লেয়ারকে পাঠানো হয়। Workspace-এ 609টা unanchored পার্ট আছে; বেশিরভাগ স্থির থাকে (sleep), তাই কোনো ডেটা পাঠায় না। কিন্তু এইগুলো কখনো থামে না:

- **Workspace/Butterflies:** ১৫টা `RotateV` জয়েন্ট প্রজাপতির ডানা অনবরত physics দিয়ে ঘোরায়। আপনার ম্যাপে আলাদা একটা **Workspace/Butterfly** ফোল্ডার আছে, যেখানে ৪৮টা ParticleEmitter দিয়ে প্রজাপতি বানানো। Particle কোনো নেটওয়ার্ক ডেটা নেয় না। **সমাধান:** physics-এর Butterflies ফোল্ডারটা মুছে দিন, অথবা এর সব পার্ট `Anchored = true` করুন।
- **Workspace/Cow:** গরুটা সার্ভারে Pathfinding করে সারাক্ষণ হাঁটে, তাই তার প্রতিটা পদক্ষেপ সবার কাছে যায়। গরু শুধু সাজানোর জিনিস, তাই প্রতিটা ক্লায়েন্ট নিজের গরু চালালেই হয় (নিচের কোড)।
- **FishingNPCS/FishLeaderboard/Dummy1:** HumanoidRootPart unanchored, তাই Humanoid কখনো ঘুমায় না। HumanoidRootPart `Anchored = true` করুন (বাকি সব NPC-তে এটা আগে থেকেই করা)।
- **Swing Set, dolna, dolna1, BikeSystem:** কেউ ব্যবহার না করলে স্থির থাকে, তাই কিছু করার দরকার নেই।

### গরুকে ক্লায়েন্টে নেওয়া

1. Workspace থেকে `Cow` মডেলটা **ReplicatedStorage**-এ সরান।
2. মডেলের ভেতরের `cow` Script-টার নাম দিন `CowAI`, আর এটাকে ModuleScript বানান। কোডের প্রথম লাইন `local character = script.Parent`-এর জায়গায় পুরো কোডটা `return function(character) ... end`-এর ভেতরে রাখুন।
3. StarterPlayer → StarterPlayerScripts-এ এই LocalScript যোগ করুন:

```lua
-- StarterPlayerScripts → LocalCow (LocalScript)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local template = ReplicatedStorage:WaitForChild("Cow")
local cow = template:Clone()
local ai = cow:FindFirstChild("CowAI")
cow.Parent = workspace

if ai then
	task.spawn(require(ai), cow)
end
```

এখন প্রতিটা প্লেয়ার নিজের ফোনে গরু হাঁটাবে, সার্ভার কিছুই পাঠাবে না। গরু একেকজনের কাছে একটু আলাদা জায়গায় থাকবে, সাজানোর জিনিসে তাতে সমস্যা নেই।

## ৩. Admin troll কমান্ড আর সার্ভারের ঘন ঘন আপডেট

**Admin Panel/AdminServer:** AdminConfig-এ `DiscoInterval = 0.5` আর `DrunkInterval = 1.2` লেখা আছে, কিন্তু কোড এগুলো ব্যবহার করে না। সব মোড প্রতি frame-এ, মানে সেকেন্ডে ৬০ বার, চলে।

- **DiscoMode** প্রতি frame-এ ক্যারেক্টারের সব পার্টের রঙ বদলায়। একটা R15 ক্যারেক্টারে accessory সহ ৪০–৮০টা পার্ট থাকে, তাই অর্থ সেকেন্ডে হাজার হাজার property আপডেট সব প্লেয়ারের কাছে যায়। একজন admin এটা চালু করলেই সবার Receive লাফিয়ে উঠবে।
- **Spin, DrunkWalk** প্রতি frame-এ HumanoidRootPart-এর CFrame বদলায়।
- **LoopReset, WalkBackwards** Heartbeat-এর ভেতরে `task.wait()` করে, ফলে প্রতি frame-এ একটা করে thread জমে।

**সমাধান:** সবচেয়ে ভালো হলো এই troll কমান্ডগুলো বন্ধ করা। রাখতে চাইলে Heartbeat-এর ভেতরে কনফিগের interval মানুন। DiscoMode-এর উদাহরণ (৫৭১–৫৭৯ নম্বর লাইনের Heartbeat অংশটা এটা দিয়ে বদলান):

```lua
local elapsed = 0
local conn = RunService.Heartbeat:Connect(function(dt)
	elapsed += dt
	if elapsed < AdminConfig.Troll.DiscoInterval then
		return
	end
	elapsed = 0
	if char and char.Parent then
		for _, part in ipairs(char:GetDescendants()) do
			if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
				part.BrickColor = BrickColor.random()
			end
		end
	end
end)
```

DrunkWalk-এ `DrunkInterval` আর LoopReset-এ `LoopResetInterval` দিয়ে একইভাবে করুন, আর Heartbeat-এর ভেতরের `task.wait(...)` মুছে দিন।

**TableTopServer/TableLearboard:** প্রতি সেকেন্ডে সব প্লেয়ারের পুরো PlayerGui ঘুরে "Refresh: 00:59" লেখা বদলায়। প্রতি ৬০ সেকেন্ডে প্রতিটা প্লেয়ারের PlayerGui-তে ১০টা নতুন সারি বানায়, ফলে প্রতিটা প্লেয়ারকে আলাদা কপি পাঠানো হয়। স্ক্রিপ্টের শেষের লুপটা (২৫১ থেকে শেষ পর্যন্ত) এটা দিয়ে বদলান:

```lua
task.spawn(actualizarTop)

while true do
	task.wait(60)
	task.spawn(actualizarTop)
end
```

আরও ভালো হয় TopUI SurfaceGui-টা StarterGui থেকে সরিয়ে সরাসরি বোর্ডের পার্টে রাখলে। তখন সবাই একটাই কপি দেখবে, আর PlayerGui লুপগুলোও বাদ দেওয়া যাবে।

**JamerLF RaisedBoard / DonateBoard:** প্রতি ২০ সেকেন্ডে টপ ডোনারের অ্যাভাটার NPC-এ আবার বসায় (`ApplyDescription`), টপ ডোনার একই থাকলেও। কোড লক করা, তাই আমি বদলাতে পারিনি। বিক্রেতা (JamerLF)-কে refresh সময় বাড়াতে বলুন, অথবা আপনার নিজের Donation লিডারবোর্ড (DonationBoardFolder) থাকলে এগুলো সরিয়ে দিন।

## ৪. Join-এর সময়ের ডাউনলোড আর ক্লায়েন্ট মেমোরি

ReplicatedStorage, ReplicatedFirst আর MaterialService-এর সব কিছু প্রতিটা প্লেয়ার গেমে ঢোকার সময় ডাউনলোড করে, আর গেম শেষ না হওয়া পর্যন্ত ফোনের মেমোরিতে রাখে। আগের স্ক্রিনশটে PC-তেই Client Memory ছিল 4.2 GB, যা কম দামের ফোনে lag আর crash-এর বড় কারণ।

| জায়গা | কী আছে | কী করবেন |
| --- | --- | --- |
| MaterialService/Ultimate Material Pack (PBR 8K) | 1,313টা MaterialVariant, কিন্তু ম্যাপে ব্যবহার হচ্ছে মাত্র ১৩টা (৭৮টা পার্টে) | ব্যবহৃত ১৩টা রেখে বাকি সব মুছুন |
| ReplicatedStorage | 12,405 instance: 2,250 ParticleEmitter, 1,249 MeshPart, 612 Sound, 662 Beam | যেগুলো শুধু সার্ভার ক্লোন করে (টুল, VFX টেমপ্লেট) সেগুলো ServerStorage-এ সরান |
| ReplicatedFirst | 1,346 instance, লোডিং স্ক্রিনের স্ক্রিপ্ট একাই 490 KB | শুধু লোডিং স্ক্রিন রাখুন, বাকি সরান |
| Workspace | 4,858 SurfaceAppearance (PBR টেক্সচার), 9,483 MeshPart | দূরের বা লুকানো জিনিস থেকে SurfaceAppearance সরান; একই টেক্সচার বারবার ব্যবহার করুন |
| StarterGui | 2,854 instance (UnoGui একাই 965) | বড় উইন্ডোগুলো দরকার হলে তখনই ক্লায়েন্টে বানান |

এগুলো চলমান Receive (প্রতি সেকেন্ডের) কমাবে না, কিন্তু join-এর সময়ের বড় স্পাইক আর ফোনের মেমোরি অনেক কমাবে। কোনো জিনিস সরানোর আগে Ctrl+Shift+F দিয়ে দেখে নিন কোনো LocalScript সেটা ReplicatedStorage থেকে খোঁজে কিনা।

## যেগুলো আগে থেকেই ঠিক আছে

এগুলো নিয়ে সময় নষ্ট করার দরকার নেই:

- StreamingEnabled চালু আছে।
- পতাকার অ্যানিমেশন (Animation Flaga local) ক্লায়েন্টে চলে (RunContext = Client)।
- লিডারবোর্ডের NPC-গুলোর HumanoidRootPart anchored (শুধু Dummy1 আর Cow বাদে)।
- Taka, Love, Time, Win বোর্ড ৬০–১০০ সেকেন্ডে একবার আপডেট হয়।
- Dance/Sync নাচ ক্লায়েন্টে চালায়।
- বেশিরভাগ ScreenGui-তে ResetOnSpawn = false।
- সার্ভারের কোনো লুপে প্রতি frame-এ `FireAllClients` পাওয়া যায়নি।
- ক্লায়েন্ট থেকে বারবার `FireServer` করা কোনো লুপও পাওয়া যায়নি।

## পরীক্ষার নিয়ম আর কাজের তালিকা

একবারে একটা করে বদলান, তারপর মাপুন। তাহলে কোন পরিবর্তনে কত কমলো বোঝা যাবে।

1. প্রতিবার প্রায় একই সংখ্যক প্লেয়ারের সার্ভারে মাপুন, কারণ Receive প্লেয়ার সংখ্যার সাথে বাড়ে।
2. Roblox Settings থেকে Performance Stats চালু করে (আপনার আগের স্ক্রিনশটের উপরের বার) Recv-এর Average অন্তত ২ মিনিট দেখুন।
3. F9 → ServerStats-এ Total Data KB/s আর প্লেয়ার সংখ্যা লিখে রাখুন (আগে ছিল 1,147 KB/s)। এটাকে প্লেয়ার সংখ্যা দিয়ে ভাগ করলে একজনের গড় Receive পাবেন।

**কাজের তালিকা (ক্রমানুসারে):**

- [ ] MaxPlayers 35–40 করুন
- [ ] StreamingTargetRadius 256 করুন
- [ ] AdminServer-এর Disco/Spin/Drunk/LoopReset বন্ধ বা interval দিয়ে ঠিক করুন
- [ ] Workspace/Butterflies মুছুন বা anchor করুন
- [ ] Cow ক্লায়েন্টে সরান
- [ ] FishLeaderboard/Dummy1-এর HumanoidRootPart anchor করুন
- [ ] TableLearboard-এর শেষ লুপ বদলান
- [ ] MaterialService-এর অব্যবহৃত ১,৩০০ material মুছুন
- [ ] ReplicatedStorage-এর সার্ভার-ওনলি জিনিস ServerStorage-এ সরান
- [ ] আগের আর পরের Recv মিলিয়ে দেখুন

সার্ভার ক্র্যাশের কাজ (মেমোরি লিক) আলাদা "সার্ভার ক্র্যাশ রিপোর্ট"-এ আছে।
