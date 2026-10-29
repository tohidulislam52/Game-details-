# সার্ভার ক্র্যাশ রিপোর্ট

Oct 29, 2026 · @Tohidul

**মূল কারণ (উচ্চ সম্ভাবনা):** প্লেয়ার গেম ছেড়ে চলে গেলেও তার Player আর Character সার্ভারের মেমোরি থেকে মুছছে না। আপনার ফাইলে Workspace-এর `PlayerCharacterDestroyBehavior` সেটিংটা `Default` (বন্ধ) অবস্থায় আছে, আর অনেক স্ক্রিপ্ট প্রতিটা প্লেয়ারের সাথে connection বাঁধে। ফলে প্রতিটা আসা-যাওয়ায় কিছু MB মেমোরি স্থায়ীভাবে আটকে থাকে, আর একদিনের হাজার হাজার আসা-যাওয়ার পর সার্ভার 11–12 GB-তে পৌঁছে ক্র্যাশ করে। একটা সেটিং বদলালেই এটা বন্ধ হওয়ার কথা।

ভিত্তি: `Bangladeshi_Tower_41.rbxl` (1,410টা স্ক্রিপ্ট, 79,459টা instance) পুরো খুলে পড়া হয়েছে, আর Creator Dashboard-এর ৯টা ক্র্যাশ সার্ভারের তথ্য। গেম চালিয়ে মাপা সম্ভব হয়নি, তাই কারণগুলো কোড পড়ে বের করা।

## ৯টা সার্ভার এক নজরে

মেমোরির পরিমাণ দেখলেই দুটো আলাদা দল বোঝা যায়: ৫ GB-এর বেশি (লিক) আর ১.৩ GB-এর কম (অন্য কারণ)। টেবিলটা মেমোরি অনুযায়ী সাজানো।

| Place version | Engine | প্লেয়ার | Frame rate | মেমোরি (MB) | ধরন |
| --- | --- | --- | --- | --- | --- |
| v3771 | 0.744 | 45 / 50 | 48 | 12,291 | ১: মেমোরি লিক |
| v3628 | 0.743 | 2 / 50 | 60 | 11,129 | ১: মেমোরি লিক |
| v3719 | 0.743 | 2 / 50 | 60 | 5,272 | ১: মেমোরি লিক (সম্ভবত) |
| v4185 | 0.745 | 0 / 50 | 60 | 1,262 | ২: খালি সার্ভার |
| v3771 | 0.744 | 1 / 50 | 60 | 1,011 | ২: খালি সার্ভার |
| v3771 | 0.744 | 1 / 50 | 60 | 914 | ২: খালি সার্ভার |
| v4185 | 0.744 | 0 / 50 | 60 | 905 | ২: খালি সার্ভার |
| v4191 | 0.745 | 1 / 50 | 60 | 893 | ২: খালি সার্ভার |
| v3796 | 0.743 | 0 / 60 | — | 888 | ৩: চালু হওয়ার সময় |

স্ক্রিনশটে প্রতিটা সার্ভার কতক্ষণ চলেছিল (uptime) সেই কলামটা নেই। ওটা পেলে লিকের গতি হিসাব করা যাবে।

## ধরন ১: মেমোরি লিক (Out of Memory)

এই ৩টা সার্ভারের মেমোরি 5–12 GB, অথচ সাধারণ গেমের সার্ভার 1.5–3 GB-এর মধ্যে থাকে। মেমোরি সীমা ছাড়ালে Roblox সার্ভারটা বন্ধ করে দেয়, আর সব প্লেয়ার একসাথে disconnect হয়।

**সবচেয়ে গুরুত্বপূর্ণ প্রমাণ: v3628 সার্ভারে মাত্র ২ জন প্লেয়ার, কিন্তু মেমোরি 11,129 MB।** অর্থাৎ প্লেয়ার চলে গেলেও তাদের জন্য বানানো জিনিস মুছছে না। অনেক ঘণ্টা ধরে অনেক প্লেয়ার আসা-যাওয়ার পর মেমোরি জমে সীমায় পৌঁছায়, তাই পুরনো সার্ভারই ক্র্যাশ করে।

v3771-এর ৪৫ জনের সার্ভারে frame rate 48-এ নেমেছিল, যা দেখায় সার্ভার ক্র্যাশের আগে ভারী হয়ে পড়ছিল। v3719 (5,272 MB, ২ জন) সম্ভবত একই লিকের মাঝপথে ছিল। ক্র্যাশের প্রকৃত কারণ Creator Dashboard-এর crash পেজে নিশ্চিত করা যাবে (নিচে সমাধান অংশে দেখুন)।

Roblox-এর সার্ভার মেমোরি সীমার একটা নির্দিষ্ট সংখ্যা অফিসিয়ালভাবে পাওয়া যায়নি; সীমাটা সার্ভারের আকার অনুযায়ী বদলায়। আপনার ১১–১২ GB-তে ক্র্যাশ হওয়া দেখে মনে হচ্ছে আপনার ৫০ জনের সার্ভারের সীমা প্রায় সেখানেই।

## মূল কারণ: চলে যাওয়া প্লেয়ারের Player ও Character মুছছে না

Roblox নিজে থেকে চলে যাওয়া প্লেয়ারের Player আর পুরনো Character মুছে দেয় না, যত্ক্ষণ না `PlayerCharacterDestroyBehavior` চালু করা হয়। কোনো স্ক্রিপ্ট `player.Chatted`, `player.CharacterAdded` বা ক্যারেক্টারের কোনো signal-এ connection বাঁধলে, সেই প্লেয়ার চলে গেলেও তার পুরো ডেটা মেমোরিতে থেকে যায়।

আপনার গেমে প্রতিটা প্লেয়ারের সাথে অনেক কিছু জড়িত:

- সার্ভারে তার PlayerGui-তে StarterGui-এর কপি (2,854টা instance)
- Backpack-এর টুল (StarterPack-এ 281টা instance, সাথে Admin/VIP টুল)
- layered clothing আর accessory সহ ক্যারেক্টার
- leaderstats আর অন্য Value

এগুলো মিলিয়ে একজন প্লেয়ারের পিছু কয়েক MB। ৫০ জনের ব্যস্ত সার্ভারে ২৪ ঘণ্টায় হাজার হাজার join-leave হয়, তাই মেমোরি ধীরে ধীরে 10 GB ছাড়িয়ে যায়। v3628 সার্ভারে মাত্র ২ জন থাকার পরও 11 GB মেমোরি, যা ঠিক এই লক্ষণ।

প্লেয়ারের সাথে connection বাঁধে এমন কয়েকটা স্ক্রিপ্ট: Zone Panel V8.5 \[Server\] (`player.Chatted`, `plr.DescendantAdded`), BTOverhead/OverheadGui Handler, CarryServer, Dance/Sync, Leaderstate create, সব লিডারবোর্ড আর দুটো Admin Panel।

**সমাধান (৫ মিনিটের কাজ):**

1. Studio-তে Explorer থেকে **Workspace** সিলেক্ট করুন।
2. Properties-এ `PlayerCharacterDestroyBehavior` খুঁজে **Enabled** করুন।
3. Publish করুন।
4. টেস্ট করুন: প্লেয়ার বের হয়ে গেলে তার ডেটা (Taka, Love, Time, Win, Donation) ঠিকমতো সেভ হচ্ছে কিনা। আপনার লিডারবোর্ড স্ক্রিপ্টগুলো ডেটা আলাদা table-এ রাখে, তাই সমস্যা হওয়ার কথা না।

এরপর কয়েক ঘণ্টা পুরনো সার্ভারের মেমোরি দেখুন। প্লেয়ার কমলে মেমোরিও কমা উচিত। তারপরও বাড়তে থাকলে নিচের "অন্য ছোট লিক" অংশটা দেখুন।

## অন্য ছোট লিক ও ভারী কাজ

এগুলো একা সার্ভার ক্র্যাশ করাবে না, কিন্তু মেমোরি বা CPU ধীরে ধীরে বাড়ায়। গুরুত্ব অনুযায়ী সাজানো।

| স্ক্রিপ্ট (কোথায়) | সমস্যা | সমাধান |
| --- | --- | --- |
| Admin Panel/AdminServer (ServerScriptService) | LoopReset আর WalkBackwards-এর Heartbeat callback-এর ভেতরে `task.wait()` আছে। ফলে প্রতি frame-এ (সেকেন্ডে ৬০টা) নতুন thread জমে। DiscoMode প্রতি frame-এ পুরো ক্যারেক্টারের রঙ বদলায়। | এই troll কমান্ডগুলো বন্ধ করুন, অথবা Heartbeat-এর বদলে `while ... task.wait(১)` লুপ ব্যবহার করুন। |
| JamerLF RaisedBoard / DonateBoard (obfuscated) | প্রতি ২০ সেকেন্ডে টপ NPC-এ `GetHumanoidDescriptionFromUserId` + `ApplyDescription` করে, টপ প্লেয়ার একই থাকলেও। | কোড লক করা, তাই বিক্রেতাকে (JamerLF) বলুন অথবা বোর্ড দুটো সরিয়ে দেখুন। |
| TableTopServer/TableLearboard | প্রতি সেকেন্ডে সব প্লেয়ারের পুরো PlayerGui `GetDescendants()` করে শুধু একটা টাইমার লেখা বদলাতে। স্ক্রিনশটে এটাই সবচেয়ে বেশি CPU নিচ্ছিল (3.3%)। | টাইমারটা বাদ দিন, অথবা ১০ সেকেন্ডে একবার করুন। বোর্ডটা StarterGui-এর বদলে Workspace-এর SurfaceGui-তে রাখুন। |
| KingEffacets/ThroneServer | `descCache`-এ সিংহাসনে বসা প্রতিটা প্লেয়ারের HumanoidDescription চিরকাল জমা থাকে। | `PlayerRemoving`-এ `descCache[player.UserId] = nil` যোগ করুন। |
| BoxingSystem/SessionTracker, InviteHandler | `sessionData` আর `PendingInvites` থেকে প্লেয়ার কখনো মোছে না। | `PlayerRemoving`-এ দুটোই `nil` করুন। |
| Zone Panel V8.5 \[Server\] | স্ক্রিনশটে Rate 10,405/s। প্রতিটা চ্যাট মেসেজে প্রতিটা প্লেয়ারের জন্য একবার করে callback চলে (`ShouldDeliverCallback`)। প্রতিটা প্লেয়ারের presence MemoryStore-এ দুটো আলাদা লুপে (৪৫ s আর ৩০ s) লেখা হয়। চলে যাওয়া প্লেয়ারের timeout ডেটা ইচ্ছা করে রেখে দেয়। | গেমে দুটো Admin Panel (Zone + Admin Panel) আছে; একটা রাখুন। Zone Panel বন্ধ করে একদিন মেমোরি দেখুন। |

obfuscated (লক করা) কোড পড়া যায় না, তাই সেগুলোতে লিক আছে কিনা নিশ্চিত বলা যাচ্ছে না: Fishing Server V14, BoxingServer, RobloxPlusDonation, MicWireHandler, Viral Wings আর ৮টা minigame স্ক্রিপ্ট।

## ধরন ২ ও ৩: খালি সার্ভারের ক্র্যাশ (888–1,262 MB)

এই ৬টা সার্ভার মেমোরির কারণে পড়েনি, কারণ মেমোরি স্বাভাবিক ছিল আর প্লেয়ার ছিল ০–১ জন। শুধু ফাইল দেখে নিশ্চিত কারণ বলা যায় না, তবে দুটো সম্ভাবনা আছে।

1. **সার্ভার বন্ধ হওয়ার সময় বেশি কাজ।** আপনার গেমে ১৭টা স্ক্রিপ্ট `BindToClose` ব্যবহার করে। Roblox সব মিলিয়ে মাত্র ৩০ সেকেন্ড সময় দেয়, তারপর জোর করে বন্ধ করে। যেমন:
   - Zone Panel webhook পাঠাতে ২০ সেকেন্ড পর্যন্ত অপেক্ষা করে।
   - লিডারবোর্ডগুলো প্রতিটা প্লেয়ারের মাঝে 0.3–0.5 সেকেন্ড থামে।
   - ServerReceiveSoftSadown সব প্লেয়ার চলে না যাওয়া পর্যন্ত `task.wait()` লুপে আটকে থাকে।

   সময় শেষ হলে সার্ভার জোর করে বন্ধ হয়, যা ক্র্যাশ হিসেবে দেখাতে পারে।
2. **পুরনো place version বা engine version-এর সার্ভার।** তালিকায় v3771 থেকে v4191 পর্যন্ত অনেক version-এর সার্ভার আছে। Roblox-এর নিজের দিকের সমস্যা (platform crash) হলে আপনার কিছু করার নেই।

v3796 (0/60, frame rate নেই) সম্ভবত চালু হওয়ার সময়ই পড়ে গেছে।

**কী করবেন:** Creator Dashboard → আপনার গেম → **Monitoring → Crashes** খুলুন। এখানে ক্র্যাশগুলো "out of memory" আর "platform" এই দুই ভাগে দেখায়। মেমোরি-ক্র্যাশের সময় নেওয়া **memory snapshot**-ও পাবেন, যেখানে দেখা যায় কোন ফোল্ডার/সার্ভিস সবচেয়ে বেশি মেমোরি নিচ্ছিল। স্ক্রিনশট দিলে আরও নিশ্চিত বলা যাবে।

## নিরাপত্তা: বাইরের সার্ভারে যোগাযোগ

পড়া যায় এমন কোডে কোনো `loadstring`, `require(সংখ্যা)` বা গোপন কোড-চালানো backdoor পাওয়া যায়নি। তবে কয়েকটা কেনা সিস্টেম নিয়মিত বাইরের সার্ভারে যোগাযোগ করে। এগুলো লক করা (obfuscated) কোড, তাই আলাদা নিরাপদ পরিবেশে চালিয়ে দেখা হয়েছে কোন URL-এ যায়।

| সিস্টেম | কোথায় যোগাযোগ করে | ঝুঁকি |
| --- | --- | --- |
| RobloxPlusDonation (JamerLF) | `pastebin.com/raw/gFKYC6Dm` (লাইসেন্স), `sentinelhook.lol` | লাইসেন্সে blacklist আছে আর কোডে `Kick` আছে, তাই বিক্রেতা দূর থেকে কাউকে বের করে দিতে পারে। |
| Fishing Server V14, BoxingServer (HYZE) | HYZE-এর Firebase ডাটাবেস (whitelist পড়ে, আবার PATCH করে ডেটা পাঠায়) | আপনার গেমের তথ্য তাদের কাছে যায়; তারা চাইলে সিস্টেম বন্ধ করতে পারে। |
| ReportConfig, Donation WebhookConfig, Zone Panel | কোডে সরাসরি Discord webhook URL লেখা | ফাইলটা যার কাছে আছে সে আপনার Discord-এ স্প্যাম করতে পারে। Zone Panel-এর কমেন্টেই বলা আছে একটা আগেই leak হয়েছিল। |

আগের স্ক্রিনশটে বারবার আসা `pastebin.com/raw/fzapfHEx` এই ফাইলের কোথাও পাওয়া যায়নি। সাথে roproxy catalog রিকুয়েস্টও ছিল, যা Donation সিস্টেম করে। তাই সম্ভবত লাইভ গেমে Donation সিস্টেমের অন্য একটা ভার্সন চলছে। নিশ্চিত হতে লাইভ ভার্সনটা Studio-তে খুলে `Ctrl+Shift+F` দিয়ে `fzapfHEx` খুঁজুন।

## সমাধানের ধাপ

- [ ] Workspace → `PlayerCharacterDestroyBehavior` = **Enabled**, তারপর publish (সবচেয়ে জরুরি)
- [ ] নিচের MemoryGuard স্ক্রিপ্টটা ServerScriptService-এ যোগ করুন, যাতে ক্র্যাশের আগেই প্লেয়াররা নতুন সার্ভারে চলে যায়
- [ ] AdminServer-এর LoopReset, WalkBackwards, DiscoMode কমান্ড বন্ধ বা ঠিক করুন
- [ ] দুটো Admin Panel-এর একটা সরিয়ে দিন
- [ ] ThroneServer, SessionTracker, InviteHandler-এ `PlayerRemoving` ক্লিনআপ যোগ করুন
- [ ] TableLearboard-এর প্রতি সেকেন্ডের PlayerGui স্ক্যান বন্ধ করুন
- [ ] সব Discord webhook মুছে নতুন বানান; নতুনগুলো কোডে সরাসরি না রেখে একটা জায়গায় রাখুন
- [ ] Monitoring → Crashes পেজ আর memory snapshot-এর স্ক্রিনশট নিন
- [ ] ২৪ ঘণ্টা পর Creator Dashboard-এ সার্ভার মেমোরি আবার দেখুন

### MemoryGuard (অস্থায়ী সুরক্ষা)

সার্ভারের মেমোরি 8,000 MB ছাড়ালে এটা সব প্লেয়ারকে একটা reserved সার্ভারে পাঠায়। আপনার আগের ServerReceiveSoftSadown স্ক্রিপ্টটা সেখান থেকে তাদের আবার নতুন পাবলিক সার্ভারে ফেরত পাঠায়। ফলে ক্র্যাশে সবাই একসাথে পড়ে যাওয়ার বদলে কয়েক সেকেন্ডের ক্লিন মুভ হয়। লিক ঠিক হয়ে গেলে এটা সরিয়ে দিন।

```lua
-- ServerScriptService → MemoryGuard (Script)
local Players = game:GetService("Players")
local Stats = game:GetService("Stats")
local TeleportService = game:GetService("TeleportService")

local LIMIT_MB = 8000     -- আপনার সার্ভার 11–12 GB-তে ক্র্যাশ করেছিল
local CHECK_EVERY = 30    -- সেকেন্ড

-- VIP বা reserved সার্ভারে চলবে না
if game.PrivateServerId ~= "" then
	return
end

local function migrate()
	local ok, code = pcall(function()
		return TeleportService:ReserveServer(game.PlaceId)
	end)
	if not ok then
		warn("[MemoryGuard] ReserveServer failed:", code)
		return false
	end
	local function send(player)
		pcall(function()
			TeleportService:TeleportToPrivateServer(game.PlaceId, code, { player }, nil, { SoftShutdown = { true, "Addition" } })
		end)
	end
	Players.PlayerAdded:Connect(send)
	for _, player in ipairs(Players:GetPlayers()) do
		send(player)
		task.wait(0.2)
	end
	return true
end

while true do
	task.wait(CHECK_EVERY)
	local mb = Stats:GetTotalMemoryUsageMb()
	if mb > LIMIT_MB then
		warn(string.format("[MemoryGuard] %.0f MB, moving players to a new server", mb))
		if migrate() then
			break
		end
	end
end
```

## Sources

- [New Player and Character Destroy Behavior (Roblox DevForum)](https://devforum.roblox.com/t/new-player-and-character-destroy-behavior/2711317)
- [Huge memory leak prevention for everyone (Roblox DevForum)](https://devforum.roblox.com/t/huge-memory-leak-prevention-for-everyone-or-most-people-atleast/3099605)
- [Server crashes chart (Roblox Creator Docs)](https://create.roblox.com/docs/production/analytics/crashes)
- [Analytics: Diagnose server crashes with server memory snapshots (Roblox DevForum)](https://devforum.roblox.com/t/analytics-diagnose-server-crashes-with-server-memory-snapshots/4525675)

এই পেজগুলোর তথ্য সার্চ ফলাফল থেকে নেওয়া; এই সেশন থেকে roblox.com সাইটগুলো সরাসরি খোলা যায়নি।
