# ESP Hub — ESP สากลสำหรับ Roblox

ESP ผู้เล่น + NPC/บอท พร้อมเมนู Rayfield ใช้ได้กับ executor ที่รองรับ Drawing API

## วิธีใช้

รันบรรทัดเดียวนี้ใน executor:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/ItsPvpMB/esp-hub/main/esp.lua"))()
```

## ปุ่มลัด

| ปุ่ม | หน้าที่ |
|---|---|
| RCtrl | เปิด/ปิด ESP (มีข้อความ "ESP: เปิด/ปิด" เด้งกลางจอ) |
| End | ปิดสคริปต์ทั้งหมด (ล้างกรอบ + ปิดเมนู) |

## ฟีเจอร์

- กล่อง + พื้นหลัง, ชื่อ, ระยะทาง, หลอดเลือด, เส้น Tracer
- จางเมื่อโดนกำแพงบัง (visibility check)
- สแกน NPC/บอทที่ไม่ใช่ player อัตโนมัติ (เดินหาโมเดลที่มี Humanoid ทั่ว Workspace)
- เช็คทีม + ใช้สีตามทีม + ปรับสีศัตรู/สีเพื่อนได้
- ระยะสูงสุดปรับได้ 100–5000 studs
- เปลี่ยนเซิร์ฟเวอร์/เทเลพอร์ตแล้วกลับมาเอง (auto requeue)
- เมนู Rayfield Gen2 ปรับได้ทุกอย่าง

## ความต้องการ

Executor ที่รองรับ `Drawing`, `queue_on_teleport` และ `HttpGet`
