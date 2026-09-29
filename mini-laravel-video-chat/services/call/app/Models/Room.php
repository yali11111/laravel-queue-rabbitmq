<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Str;

class Room extends Model
{
    protected $fillable = [
        'room_id',
        'name',
    ];

    protected static function booted()
    {
        static::creating(function ($room) {
            if (!$room->room_id) {
                $room->room_id = (string) Str::uuid();
            }
        });
    }
}
