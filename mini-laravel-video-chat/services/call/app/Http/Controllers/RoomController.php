<?php

namespace App\Http\Controllers;

use App\Models\Room;
use Illuminate\Http\Request;

class RoomController extends Controller
{
    public function store(Request $request)
    {
        $room = Room::create([
            'name' => $request->input('name'),
        ]);

        return response()->json([
            'success' => true,
            'room' => [
                'id' => $room->room_id,
                'name' => $room->name,
            ],
        ], 201);
    }

    public function show(string $roomId)
    {
        $room = Room::where('room_id', $roomId)->first();

        if (!$room) {
            return response()->json([
                'success' => false,
                'message' => 'Room not found',
            ], 404);
        }

        return response()->json([
            'success' => true,
            'room' => [
                'id' => $room->room_id,
                'name' => $room->name,
            ],
        ]);
    }

    public function destroy(string $roomId)
    {
        $room = Room::where('room_id', $roomId)->first();

        if (!$room) {
            return response()->json([
                'success' => false,
                'message' => 'Room not found',
            ], 404);
        }

        $room->delete();

        return response()->json([
            'success' => true,
        ]);
    }
}
